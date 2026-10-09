#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/.." rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

DRY_RUN=0

if [[ $# -gt 1 ]]; then
    echo "Использование: $0 [--dry-run]" >&2
    exit 1
fi

if [[ $# -eq 1 ]]; then
    if [[ "$1" != "--dry-run" ]]; then
        echo "Неизвестный аргумент: $1" >&2
        exit 1
    fi
    DRY_RUN=1
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: отсутствует site/index.html" >&2
    exit 1
fi

if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения" >&2
    exit 1
fi

if [[ ! -f "${CA_CERT}" ]]; then
    echo "Ошибка: не найден сертификат ${CA_CERT}" >&2
    exit 1
fi

RSYNC_ARGS=(
    -avz
    --delete
    --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5"
)

if [[ ${DRY_RUN} -eq 1 ]]; then
    RSYNC_ARGS+=(--dry-run)
fi

rsync "${RSYNC_ARGS[@]}" \
    "${LOCAL_DIR}" \
    "${REMOTE}:${REMOTE_DIR}/"

if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "Пробный запуск завершён: сервер не изменён"
    exit 0
fi

if ! curl --fail --silent --show-error \
    --cacert "${CA_CERT}" "${SITE_URL}" >/dev/null; then
    echo "Ошибка: проверка доступности ресурса не пройдена" >&2
    exit 1
fi

COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
echo "Доставлен коммит ${COMMIT}"
