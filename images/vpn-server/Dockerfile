# Servidor L2TP para o node pool `zisp`. Nao existe imagem oficial de xl2tpd,
# entao ela e construida aqui e publicada no mesmo ACR das aplicacoes.
#
# Ubuntu 24.04 de proposito, casando com a imagem de no do AKS: o modprobe
# roda contra o kernel do HOST, e o pacote de modulos tem que ser o da mesma
# distro para o `modinfo` e o `insmod` acharem o .ko em /lib/modules.
FROM ubuntu:24.04

# DEBIAN_FRONTEND: o postinst do xl2tpd abre prompt de configuracao e o build
# travaria esperando entrada.
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      xl2tpd \
      ppp \
      iptables \
      iproute2 \
      kmod \
      # python3 completo, NAO python3-minimal: o minimal vem sem a stdlib e
      # o hook morre em `import json`. E morre calado -- run-parts ignora
      # codigo de saida e o /etc/ppp/ip-up tem `|| true`, entao o sintoma
      # seria "o painel nao detecta conexao", sem nenhum erro em log.
      python3 \
      procps \
      iputils-ping && \
    rm -rf /var/lib/apt/lists/*

# Os hooks do pppd. Vem como arquivo na imagem, e nao por ConfigMap, porque
# precisam de bit de execucao: ConfigMap monta com defaultMode mas o pppd
# executa via run-parts e qualquer surpresa de permissao vira falha silenciosa
# na notificacao de conexao.
COPY zisp-ppp-connections.py /usr/local/sbin/zisp-ppp-connections.py
COPY ip-up-99-zisp-notify   /etc/ppp/ip-up.d/99-zisp-notify
COPY ip-down-99-zisp-notify /etc/ppp/ip-down.d/99-zisp-notify
COPY entrypoint.sh          /usr/local/sbin/entrypoint.sh

# O pacote ppp do Debian/Ubuntu ja roda ip-up.d/ip-down.d, mas so se /etc/ppp/ip-up
# existir e chamar run-parts. A imagem base nao traz os dois arquivos.
RUN printf '#!/bin/bash\nrun-parts /etc/ppp/ip-up.d 2>/dev/null || true\n'   > /etc/ppp/ip-up && \
    printf '#!/bin/bash\nrun-parts /etc/ppp/ip-down.d 2>/dev/null || true\n' > /etc/ppp/ip-down && \
    chmod 0755 /etc/ppp/ip-up /etc/ppp/ip-down \
               /etc/ppp/ip-up.d/99-zisp-notify /etc/ppp/ip-down.d/99-zisp-notify \
               /usr/local/sbin/zisp-ppp-connections.py \
               /usr/local/sbin/entrypoint.sh

ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
