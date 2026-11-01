#!/usr/bin/env python3
"""Create or update the Simplaca Kubernetes Secret from CI environment variables."""

import base64
import json
import os
import subprocess
import sys


REQUIRED = (
    "NODE_ENV",
    "PORT",
    "PLACAS_API_BASE_URL",
    "REPORT_PRICE_CENTS",
    "SMTP_HOST",
    "SMTP_PORT",
    "FROM_EMAIL",
    "FROM_NAME",
    "BLOG_ADMIN_EMAIL",
    "DATABASE_URL",
    "PLACAS_API_TOKEN",
    "IUGU_API_TOKEN",
    "IUGU_WEBHOOK_SECRET",
    "SMTP_USERNAME",
    "SMTP_PASSWORD",
    "BLOG_ADMIN_PASSWORD",
    "BLOG_ADMIN_SECRET",
)
OPTIONAL = ("JWT_SECRET",)


def main() -> int:
    missing = [key for key in REQUIRED if not os.environ.get(key)]
    if missing:
        print("Missing Simplaca secrets: " + ", ".join(missing), file=sys.stderr)
        return 1

    values = {
        key: os.environ[key]
        for key in REQUIRED + OPTIONAL
        if os.environ.get(key)
    }
    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": "simplaca-api-env", "namespace": "simplaca"},
        "type": "Opaque",
        "data": {
            key: base64.b64encode(value.encode()).decode()
            for key, value in values.items()
        },
    }
    subprocess.run(
        ["kubectl", "apply", "--server-side", "--field-manager=byteflip-infra", "-f", "-"],
        input=json.dumps(secret),
        text=True,
        check=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
