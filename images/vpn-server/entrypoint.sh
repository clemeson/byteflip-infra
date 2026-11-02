#!/bin/bash
# Sobe o xl2tpd no no do AKS. Substitui o que no Ansible eram tres coisas
# separadas: o role `common` (modulos + sysctl), o `zisp-vpn-rules.service`
# (iptables) e o systemd do xl2tpd.
set -euo pipefail

log() { echo "[vpn-server] $*"; }
die() { echo "[vpn-server] ERRO: $*" >&2; exit 1; }

: "${VPN_NETWORK:?VPN_NETWORK nao definida}"
: "${VPN_GATEWAY:?VPN_GATEWAY nao definida}"

# ---------------------------------------------------------------------------
# Modulos de kernel
#
# Verificado em 02/11/2026 na imagem AKSUbuntu-2404 (kernel 6.8.0-1071-azure):
# linux-modules-extra esta instalado e os tres .ko existem. Isto aqui nao e
# por desconfianca da imagem de hoje — e porque o no e REIMAGEADO em upgrade
# de node image, e a imagem nova pode nao trazer o pacote.
#
# Falhar aqui e o ponto central: sem l2tp_ppp o xl2tpd SOBE, ABRE a porta,
# ACEITA a conexao e o tunel nunca fecha. Nenhum log, nenhum crash, e horas
# procurando no lugar errado. Com o modprobe antes do xl2tpd, o pod entra em
# CrashLoopBackOff com a causa escrita.
#
# `pppol2tp` NAO esta na lista: nao existe neste kernel, nem como alias
# (modules.alias tem zero entradas). O role do Ansible o listava e falharia
# aqui. `ppp_generic` tambem fica fora: e builtin, e /dev/ppp ja existe.
# ---------------------------------------------------------------------------
log "kernel $(uname -r)"
# modprobe resolve as dependencias (l2tp_netlink, l2tp_core, pppox) sozinho.
if ! modprobe l2tp_ppp 2>/dev/null; then
  if ! grep -q '^l2tp_ppp' /proc/modules; then
    die "l2tp_ppp nao carregou. Sem ele o xl2tpd aceita conexao e o tunel
    nunca fecha. Confira se linux-modules-extra-$(uname -r) esta na imagem do
    no: a cada upgrade de node image isto pode mudar.
      az vmss run-command invoke -g MC_<rg> -n <vmss> --instance-id 0 \\
        --command-id RunShellScript --scripts 'modinfo -n l2tp_ppp'"
  fi
fi
log "l2tp_ppp ok"
[[ -c /dev/ppp ]] || die "/dev/ppp ausente. O container precisa de privileged: true."

# ---------------------------------------------------------------------------
# sysctl
#
# ip_forward NAO esta aqui: o kube-proxy ja o deixa em 1 em todo no do AKS.
#
# rp_filter esta, e e obrigatorio: no no ele vem 1, e o pppd cria rota por
# peer de forma assimetrica — com o filtro de caminho reverso ligado o
# trafego do tunel e descartado SEM log. O kernel usa
# max(conf.all, conf.<iface>), e interface nova herda de conf.default, entao
# os dois precisam ir a zero para as pppX que ainda nao existem.
#
# Custo honesto: isto afeta o host netns do no, nao so este pod. Baixar
# rp_filter relaxa a protecao contra IP spoofado no encaminhamento desse no.
# E o preco de terminar tunel num no de Kubernetes.
# ---------------------------------------------------------------------------
sysctl -qw net.ipv4.conf.all.rp_filter=0
sysctl -qw net.ipv4.conf.default.rp_filter=0
log "rp_filter=0 (all, default); ip_forward=$(sysctl -n net.ipv4.ip_forward)"

# ---------------------------------------------------------------------------
# iptables
#
# Nada de iptables-persistent nem de save/restore: o kube-proxy programa as
# proprias cadeias e as reconcilia em runtime. Um retrato de TODAS as regras
# restaurado depois quebraria a rede do cluster de um jeito dificil de achar.
# Aqui so as regras da VPN, cada uma testada com -C antes de -A para ser
# idempotente (o pod reinicia e nao deve duplicar nada).
# ---------------------------------------------------------------------------
IFACE="$(ip route show default | awk '{print $5}' | head -1)"
[[ -n "$IFACE" ]] || die "nao achei a interface default"
log "interface default: $IFACE"

add() {
  local table=$1; shift
  iptables -t "$table" -C "$@" 2>/dev/null || iptables -t "$table" -A "$@"
}

# Encaminhamento nos dois sentidos do tunel.
add filter FORWARD -s "$VPN_NETWORK" -j ACCEPT
add filter FORWARD -d "$VPN_NETWORK" -j ACCEPT

# Saida do cliente VPN para a internet.
add nat POSTROUTING -s "$VPN_NETWORK" ! -d "$VPN_NETWORK" -o "$IFACE" -j MASQUERADE

# ESTA e a regra que nao existia no setup antigo, e sem ela o zisp-api abre
# conexao com o Mikrotik e nunca recebe resposta.
#
# O pod do zisp-api tem IP da VNet (10.80.x.x, Azure CNI). Sem SNAT o Mikrotik
# ve essa origem, nao tem rota para 10.80.0.0/16, e responde pelo default
# gateway dele — ou seja, pela internet do cliente. O pacote se perde e a
# conexao fica pendurada.
#
# Com o SNAT o Mikrotik ve tudo vindo do gateway do tunel, responde pelo
# tunel sem saber que existe Kubernetes, e nenhum CPE precisa de rota
# estatica. Bonus: a origem passa a ser estavel, o que da para usar em regra
# de firewall no RouterOS.
add nat POSTROUTING -d "$VPN_NETWORK" -o 'ppp+' -j SNAT --to-source "$VPN_GATEWAY"
log "iptables aplicado (SNAT pod->MK para $VPN_GATEWAY)"

# ---------------------------------------------------------------------------
# chap-secrets
#
# Mora no PVC, nao em hostPath: em hostPath ele morreria na reimagem do no e
# todos os tuneis cairiam ate a conciliacao reescrever do banco — que roda de
# 6 em 6 horas. O zisp-vpn-api monta o MESMO PVC e escreve neste arquivo.
#
# So cria se ausente. Sobrescrever derrubaria todo cliente em campo: foi o
# que causou o incidente de conciliacao que apagou usuarios.
# ---------------------------------------------------------------------------
if [[ ! -f "$CHAP_SECRETS" ]]; then
  log "criando $CHAP_SECRETS (curinga; conteudo real vem do zisp-vpn-api)"
  printf '# client\tserver\tsecret\tIP\n*\tl2tpd\t*\t*\n' > "$CHAP_SECRETS"
fi
chmod 0600 "$CHAP_SECRETS"
ln -sf "$CHAP_SECRETS" /etc/ppp/chap-secrets

mkdir -p /var/run/ppp /var/run/xl2tpd
# O xl2tpd precisa deste fifo e nao o cria sozinho.
[[ -p /var/run/xl2tpd/l2tp-control ]] || mkfifo /var/run/xl2tpd/l2tp-control

# -D: foreground. O pod E o supervisor, nao o systemd.
log "iniciando xl2tpd"
exec xl2tpd -D -c /etc/xl2tpd/xl2tpd.conf
