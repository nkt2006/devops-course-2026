# Результаты практической работы №11

Проверки выполнены на существующей VM Ubuntu 24.04.5 ARM64 после отката
к `01-clean-install`. Предыдущее состояние сохранено в `08-before-ansible`.
Управляющий узел: macOS, Ansible Core 2.21.5. На VM установлен Docker 29.10.0
из официального Docker-репозитория для noble/arm64.

## Итоги запусков

| Запуск | ok | changed | unreachable | failed |
|---|---:|---:|---:|---:|
| 01-bootstrap | 27 | 16 | 0 | 0 |
| 08-idempotent | 24 | 0 | 0 | 0 |
| 11-repair-drift | 26 | 3 | 0 | 0 |
| 14-missing-image-tag | 21 | 0 | 0 | 1 |
| 17-restored-sha | 24 | 0 | 0 | 0 |
| 19-audit-first | 8 | 0 | 0 | 0 |
| 20-audit-second | 8 | 0 | 0 | 0 |
| 22-audit-detects-stopped-container | 5 | 0 | 0 | 1 |
| 23-restore-after-negative-audit | 24 | 1 | 0 | 0 |
| 25-final-audit | 8 | 0 | 0 | 0 |

Первый запуск выполнен от student с запросами SSH/sudo пароля. Последующие
запуски выполнены от devops по ключу. Проверки whoami, sudo -n true и
ansible ping успешны. Password-only подключение student отвергнуто
с `Permission denied (publickey)`.

## Drift

Удалён контейнер devops-ci-app, upstream Nginx заменён с 5000 на 5001.
Внешний GET /health вернул 502. Один site.yml восстановил шаблон Nginx
и контейнер; handler проверил конфигурацию и перезагрузил Nginx.
Три изменения: шаблон, контейнер, reload. Внешний health снова вернул 200
и JSON `{"status":"ok"}`.

## Недоступный тег

Тег временно заменён на `0000000000000000000000000000000000000000`.
Задача Pull reviewed application image before changing the running container
получила 404 Not Found при обращении к GHCR. Следующая задача управления
контейнером не выполнялась. Прежний полный ID контейнера сохранён:
`d3ecb3d5d8727cf279402621fa56e1876a70a4ad803b624e24dcee4aa50d0278`.
Внешний health остался 200. Переменная восстановлена из Git; повторный
site.yml завершился с changed=0, failed=0.

## Аудит и конечное состояние

verify.yml дважды завершился с changed=0. После docker stop он завершился
с failed=1 на утверждении о работающем контейнере и ничего не исправил.
site.yml запустил контейнер, изменив одну задачу. Финальный внешний health
и read-only аудит успешны. Контейнер использует образ
`ghcr.io/nkt2006/devops-ci-app:bbdd43205cf5daf40fb07f3013617449d3c70276`.

Публикация: `127.0.0.1:5000->5000/tcp`; Nginx — HTTP 80. UFW активен,
входящие по умолчанию deny, исходящие allow, разрешены 22/tcp и 80/tcp.
Эффективные параметры SSH: port 22, permitrootlogin no,
passwordauthentication no. Приватные ключи и пароли в Git не добавлялись.

На Ansible Core 2.21 коллекции закреплённых учебных версий выводят
предупреждения об API, которые будут удалены в Core 2.24. В текущем
окружении все предусмотренные проверки прошли; перед обновлением Core
нужно проверить совместимость коллекций.
