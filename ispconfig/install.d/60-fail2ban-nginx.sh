    #!/usr/bin/env bash
    set -euo pipefail

    echo "🛡️  Configurando Fail2Ban para NGINX req-limit..."
    cat > /etc/fail2ban/jail.d/nginx-custom.conf <<'EOF'
[nginx-req-limit]
enabled = true
filter = nginx-req-limit
action = iptables-multiport[name=ReqLimit, port="http,https", protocol=tcp]
logpath = /var/log/nginx/*error.log
findtime = 600
bantime = 7200
maxretry = 10
EOF

    cat > /etc/fail2ban/filter.d/nginx-req-limit.conf <<'EOF'
[Definition]
failregex = limiting requests.*client: <HOST>
ignoreregex =
EOF

    systemctl restart fail2ban
    echo "✅ Fail2Ban reiniciado."
