#!/usr/bin/env bash
set -euo pipefail
source /opt/ispconfig-env.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for step in $(ls -1 ${DIR}/install.d | sort); do
  echo -e "\n  Executando etapa: $step"
  bash "${DIR}/install.d/$step"
done
echo -e "\n Todas as etapas concluídas com sucesso."
