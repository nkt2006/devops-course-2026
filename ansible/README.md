# Практическая работа №11: управление конфигурацией

Управляющий узел — macOS Apple Silicon, управляемый — существующая Ubuntu
Server 24.04 ARM64 `devops-vm`. В отличие от примера amd64 в методичке роль
`base` проверяет `aarch64` и подключает официальный Docker-репозиторий для
`arm64`. Сборки приложения на VM нет.

Перед откатом к `01-clean-install` сохранён снимок `08-before-ansible`.
Предыдущие практические работы можно восстановить из этого снимка.

## Подготовка и первичный запуск

На исходном чистом снимке создан только `devops`. Пользователя `student`
нужно предварительно создать из этой административной учётной записи
через `sudo adduser --gecos "" student` и `sudo usermod -aG sudo student`.
Пароль задаётся в терминале; в Git он не сохраняется.

```bash
ansible-galaxy collection install -r ansible/requirements.yml
cd ansible
ansible-inventory -i inventory/bootstrap.ini --graph
ansible-inventory --graph
ansible-playbook -i inventory/bootstrap.ini site.yml --syntax-check
ansible-playbook site.yml --syntax-check
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_devops_vm
ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass
```

Используется существующий ключ `id_ed25519_devops_vm`. При запросах SSH и
BECOME вводится пароль `student`. Ansible Core 2.21 передаёт SSH-пароль
через встроенный механизм SSH_ASKPASS; отдельный `sshpass` ему не нужен.
Версии коллекций закреплены в `requirements.yml` по методическим указаниям.
Проверка ключа хоста SSH включена. Если VM переустановлена и ключ изменился,
сначала сверяется fingerprint через консоль VM, затем обновляется known_hosts.

## Работа по ключу

```bash
ssh -i ~/.ssh/id_ed25519_devops_vm devops@192.168.56.3 \
  'whoami && sudo -n true && echo sudo-ok'
ansible all -m ping
curl --fail http://192.168.56.3/health
curl --fail http://192.168.56.3/
ansible-playbook site.yml
ansible-playbook verify.yml
ansible-playbook verify.yml
```

В повторном `site.yml` и в обоих запусках аудита ожидаются `changed=0`,
`failed=0`. Аудит не ремонтирует конфигурацию.

## Разделение ролей

| Роль | Конечное состояние |
|---|---|
| `base` | Ubuntu 24.04 ARM64, зависимости модулей, официальный Docker Engine |
| `ssh` | ключ devops, sudo, запрет паролей и root, UFW разрешает 22 и 80 |
| `nginx` | HTTP reverse proxy на loopback приложения, default site удалён |
| `app` | образ GHCR по полному SHA, контейнер, проверка JSON `/health` |

`python3-debian` и `python3-requests` устанавливаются на VM, где работают
модули. Коллекции устанавливаются на Mac. Docker SDK for Python не нужен.
Пользователь `devops` получает полный sudo без пароля для учебной
автоматизации. Его ключ и членство в группе docker дают административный
доступ; в производственной среде такие права требуют ограничения.

Сначала устанавливается открытый ключ, затем отключаются пароли. Файл
`00-ansible-hardening.conf` читается до cloud-init. Конфигурации sudoers и
SSH проверяются до записи. `force_handlers = True` обеспечивает применение
уведомлённых изменений даже при отказе поздней задачи. Перед reload Nginx
отдельный handler выполняет `nginx -t`.

Приложение публикуется только на `127.0.0.1:5000`; извне работает Nginx на
80. У Docker собственные правила фильтрации, поэтому один UFW не заменяет
привязку к loopback. HTTPS и прежний SSH-порт 2222 в этой работе не используются.

## Учебные инциденты

Удалить контейнер и заменить upstream 5000 на 5001 в активном конфиге
Nginx, проверить конфиг и reload; внешний `/health` должен вернуть 502.
Восстановление выполняется только `ansible-playbook site.yml`.

Для второго инцидента временно заменить `app_tag` в `group_vars/all.yml`
на 40 нулей. Pull отсутствующего образа должен завершиться ошибкой до
изменения существующего контейнера; прежний ID и внешний health 200
должны сохраниться. Затем `git restore ansible/group_vars/all.yml` из корня
репозитория и повторить `site.yml`.

Для отрицательного теста аудита остановить только `devops-ci-app`, запустить
`verify.yml` и получить отказ. Затем восстановить `site.yml` и проверить
внешний health. Конкретный SHA хранится только в `group_vars/all.yml`;
не следует редактировать роль при обновлении версии.
