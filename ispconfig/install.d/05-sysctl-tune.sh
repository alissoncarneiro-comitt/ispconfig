#!/usr/bin/env bash
set -euo pipefail

echo "⚙️ Aplicando ajustes de desempenho no sysctl..."

SYSCTL_FILE="/etc/sysctl.d/99-performance.conf"
SOURCE_FILE="./conf/sysctl.conf"

mkdir -p /etc/sysctl.d/

if [ -f "$SOURCE_FILE" ]; then
  cp "$SOURCE_FILE" "$SYSCTL_FILE"
  sysctl --system
  echo "✅ sysctl tuning aplicado com sucesso!"
else
  echo "❌ Arquivo $SOURCE_FILE não encontrado. Pulei ajustes do sysctl."
fi
