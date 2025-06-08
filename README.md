# Infraestrutura Laravel com ISPConfig + NGINX Otimizado + PHP Multi-versão

Este projeto provisiona uma stack profissional de hospedagem em servidores Debian para aplicações Laravel, WordPress e sistemas PHP modernos, com foco em **performance**, **segurança** e **automação**.

---

## PRD - Documento de Requisitos do Projeto

> **Objetivo:**  
> Criar uma infraestrutura automatizada, escalável e performática para hospedar múltiplas aplicações PHP (Laravel, WordPress, SaaS), com suporte à gestão via ISPConfig e monitoramento integrado.

### Funcionalidades esperadas:

- ISPConfig configurado com pools PHP-FPM via socket e templates Laravel/WordPress
- NGINX compilado com módulos essenciais de performance e segurança
- Suporte a múltiplas versões do PHP (8.2 / 8.3 / 8.4)
- Rclone configurado para backup automatizado no Google Drive
- Exporters para Prometheus (Node, NGINX, PHP, MariaDB)
- Dashboard Grafana instalado e pronto para uso
- Fail2Ban configurado para proteger o stack web
- Arquitetura modular, com scripts reutilizáveis e separados por contexto

### Público-alvo:

- DevOps/SREs que desejam infraestrutura sob controle com alto desempenho
- Agências que hospedam múltiplos sites por cliente
- Times que mantêm sistemas Laravel ou SaaS com customizações de PHP
- Ambientes com necessidades de tuning fino no kernel e no stack

---

## Principais Tecnologias

- **NGINX compilado** com Brotli, HTTP/3 (QUIC), GeoIP2, ngx_pagespeed, njs, headers-more
- **PHP 8.2 / 8.3 / 8.4** via socket + `update-alternatives` + extensões PECL
- **ISPConfig** com pools otimizados por socket e template NGINX compatível com Laravel
- **Prometheus + Grafana** com exporters para Node, NGINX, PHP-FPM e MariaDB
- **Backups via Rclone + GDrive**
- Arquitetura modular, clara e reutilizável

---

## Estrutura dos Diretórios

```
.
├── bootstrap-install.sh       # Instalador principal
├── db/
│   ├── 50-server-optimized-32gb.cnf
├── nginx/
│   ├── setup.sh               # Compila e instala NGINX com todos os módulos
│   ├── conf.d/                # Extras opcionais
│       └──nginx.conf
│   ├── snippets/              # Include padrão (SSL, Headers, etc.)
│       ├── fastcgi-cache.conf
│       ├── fastcgi-php.conf
│       ├── laravel.conf
│       ├── security-headers.conf
│       ├── ssl-params.conf
│       └── wordpress.conf
│   └── templates/
│       └── nginx_vhost.conf.master
├── php/
│   ├── setup-fpm.sh           # Instala versões PHP + pools.d customizados
│   └── pools.d/               # Configurações de pools FPM
├── ispconfig/
│   ├── conf/sysctl.conf       # Ajustes de kernel e file descriptors
│   ├── env.sh                 # Variáveis globais
│   ├── main-install.sh        # Runner das etapas
│   └── install.d/             # Scripts passo a passo
│       ├── 00-packages.sh
│       ├── 05-sysctl-tune.sh
│       ├── 10-mariadb-tune.sh
│       ├── 20-rclone-check.sh
│       ├── 30-exporter-user.sh
│       ├── 40-ispconfig-auto.sh
│       ├── 50-backup-gdrive.sh
│       └── 60-fail2ban-nginx.sh
├── monitoring/
│   ├── setup.sh
│   ├── grafana.sh
│   ├── prometheus.sh
│   └── exporters/
│       ├── node_exporter.sh
│       ├── nginx_exporter.sh
│       ├── php_fpm_exporter.sh
│       └── mysqld_exporter.sh
```

---

## Como usar

```bash
chmod +x bootstrap-install.sh
sudo ./bootstrap-install.sh
```

> O script detecta automaticamente Debian 11/12 e já aplica ajustes para produção.

---

## Pré-requisitos

- Debian 11 ou 12 limpo
- Usuário com permissões `sudo`
- DNS apontado para o IP (necessário para Let’s Encrypt)

---

## Vantagens desta stack

- Compatível com **Laravel**, **WordPress** e qualquer app PHP moderno
- Backups automáticos no Google Drive com agendamento via `cron`
- Monitoramento completo com Prometheus e dashboards prontos para Grafana
- Segurança reforçada com Fail2Ban e headers de hardening

---

## Após instalação

- Acesse o ISPConfig via: `https://<seu-ip-ou-dominio>:8080`
- Crie seu site e escolha o **template NGINX Laravel** (adaptado com suporte a socket)
- O PHP será executado via `/run/php/php{versão}-fpm.sock`

---

## Autor

Desenvolvido por **Alison Carneiro**
