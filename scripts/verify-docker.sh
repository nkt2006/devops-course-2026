#!/usr/bin/env bash
# Проверки ПР7, требующие sudo. Секреты окружения не выводятся.
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
    echo "Запустите через sudo" >&2
    exit 1
fi
project=/home/devops/app
evidence=/home/devops/practice7-evidence
mkdir -p "$evidence"
exec > >(tee "$evidence/07-privileged-checks.log") 2>&1
export APP_PROJECT_DIR="$project"
cd "$project"
original="$(mktemp)"
cp docker-compose.yml "$original"
restore() {
    cat "$original" > "$project/docker-compose.yml"
    docker compose up -d --wait --wait-timeout 120
    docker stop exposed >/dev/null 2>&1 || true
}
trap restore EXIT

set -x
nginx -t
ufw status verbose
getent group docker
bash /home/devops/audit.sh
echo "audit normal exit=0"

docker run -d --rm --name exposed -p 5001:5000 devops-app:1.0
ufw status | grep 5001 || true
iptables -t nat -L DOCKER -n | grep 5001
docker stop exposed

sed 's/127.0.0.1:5000:5000/5000:5000/' "$original" > docker-compose.yml
docker compose up -d --wait --wait-timeout 120
ss -tln | grep -E ':(5000|5432)\b'
set +e
bash /home/devops/audit.sh
negative_code=$?
set -e
echo "audit exposed port exit=$negative_code"
[[ $negative_code -eq 1 ]]

cat "$original" > docker-compose.yml
docker compose up -d --wait --wait-timeout 120
bash /home/devops/audit.sh
echo "audit restored exit=0"
echo "Проверки завершены. Безопасная конфигурация восстановлена."
