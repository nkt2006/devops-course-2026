#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK]   $desc"
        ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" \
    "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" \
    "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

ssh_port="$(sudo sshd -T | awk '/^port/{print $2; exit}')"
if [[ "$ssh_port" != "22" ]]; then
    echo " [OK]   Порт SSH отличается от стандартного 22 (текущий: $ssh_port)"
    ((PASS++))
else
    echo " [FAIL] Порт SSH отличается от стандартного 22 (получено: '$ssh_port')"
    ((FAIL++))
fi

check "MaxAuthTries равен 3" \
    "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" \
    "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика входящего трафика равна deny" \
    "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "              %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" \
    "active" "$(systemctl is-active nginx 2>/dev/null || true)"

if sudo nginx -t >/dev/null 2>&1; then
    nginx_config="ok"
else
    nginx_config="error"
fi
check "Конфигурация nginx синтаксически корректна" \
    "ok" "$nginx_config"

cert_checkend_seconds="${CERT_CHECKEND_SECONDS:-2592000}"
if openssl x509 -checkend "$cert_checkend_seconds" -noout \
    -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then
    cert_valid="yes"
else
    cert_valid="no"
fi
check "Сертификат не истекает в течение $cert_checkend_seconds секунд" \
    "yes" "$cert_valid"

world_writable="$(find /var/www/devops-site -type f -perm -o+w -print -quit 2>/dev/null)"
check "Нет файлов, доступных для записи всем" \
    "" "$world_writable"

check "Права закрытого ключа равны 600" \
    "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)"

echo "[5] Контейнеризация"
check "Служба docker активна" \
    "active" "$(systemctl is-active docker 2>/dev/null)"

check "Контейнер СУБД находится в состоянии healthy" \
    "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"

if sockets="$(ss -H -ltn 2>/dev/null)"; then
    unsafe_ports="$(awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127[.]0[.]0[.]1:/ {print $4}' <<< "$sockets")"
    if [[ -z "$unsafe_ports" ]] && awk '$4 == "127.0.0.1:5000" {found=1} END {exit !found}' <<< "$sockets"; then
        ports_safe=yes
    else
        ports_safe=no
    fi
else
    ports_safe=no
fi
check "Порт приложения доступен только на 127.0.0.1, внешних портов 5000 и 5432 нет" \
    "yes" "$ports_safe"

# При запуске через sudo проверяем проект исходного пользователя.
project_user="${SUDO_USER:-$USER}"
project_home="$(getent passwd "$project_user" | cut -d: -f6)"
project_dir="${APP_PROJECT_DIR:-${project_home}/app}"
check "Права файла окружения равны 600" \
    "600" "$(stat -c '%a' "$project_dir/.env" 2>/dev/null)"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
