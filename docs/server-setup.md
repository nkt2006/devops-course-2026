# Конфигурация виртуальной машины devops-vm

Документ фиксирует итоговую конфигурацию практической работы № 5 и порядок её восстановления после отката к снимку `01-clean-install`.

## 1. Параметры машины

- Гипервизор: Oracle VirtualBox 7.2.20 на macOS (Apple Silicon).
- Гостевая ОС: Ubuntu Server 24.04.5 LTS ARM64.
- Оперативная память: 2048 МБ.
- Процессоры: 2 виртуальных ядра.
- Диск: динамический VDI объёмом 20,46 ГБ.
- Загрузка: EFI.

## 2. Сетевые интерфейсы

| Интерфейс Ubuntu | Тип адаптера | IPv4-адрес | Назначение |
|---|---|---|---|
| `enp0s8` | NAT | `10.0.2.15/24` | Исходящий доступ в Интернет |
| `enp0s9` | Host-only (`devops-hostonly`) | `192.168.56.3/24` | Связь между Mac и ВМ |

Host-only сеть VirtualBox использует диапазон `192.168.56.0/24`. Адрес Mac в этом сегменте - `192.168.56.2`.

Проверка внутри Ubuntu:

```bash
ip -brief address
```

## 3. Правило проброса портов

Итоговое правило адаптера NAT:

| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
|---|---|---|---:|---|---:|
| `ssh` | TCP | `127.0.0.1` | 2222 | не задан | 2222 |

При восстановлении со снимка `01-clean-install` сначала используется гостевой порт `22`, а после усиления SSH правило изменяется на гостевой порт `2222`.

На macOS правило можно создать командами:

```bash
VBoxManage controlvm "devops-vm" natpf1 "ssh,tcp,127.0.0.1,2222,,22"
# После изменения порта sshd:
VBoxManage controlvm "devops-vm" natpf1 delete "ssh"
VBoxManage controlvm "devops-vm" natpf1 "ssh,tcp,127.0.0.1,2222,,2222"
```

## 4. Учётные записи

- Основная учётная запись: `devops`.
- Пользователь входит в группу `sudo` и выполняет административные команды через `sudo`.
- Удалённый вход выполняется только по ключу Ed25519.
- Закрытый ключ на Mac: `~/.ssh/id_ed25519_devops_vm`.
- Открытый ключ на сервере: `~/.ssh/authorized_keys`.
- Права: `700` для `~/.ssh`, `600` для `authorized_keys`.

Создание и установка ключа с Mac:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_devops_vm -C "devops-vm"
cat ~/.ssh/id_ed25519_devops_vm.pub | ssh devops@192.168.56.3 \
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_devops_vm
```

Профиль `~/.ssh/config` на Mac:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/id_ed25519_devops_vm
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes
```

## 5. Служба SSH

- Служба: `ssh.service`.
- Порт: `2222/tcp`.
- Файл усиления: `/etc/ssh/sshd_config.d/99-hardening.conf`.
- Резервная копия: `/etc/ssh/sshd_config.backup`.
- Socket-активация `ssh.socket` отключена.

Содержимое `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

В `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` закомментирована, чтобы более ранний файл не переопределял запрет парольного входа.

Команды восстановления и проверки:

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo sed -i 's/^PasswordAuthentication yes/# PasswordAuthentication yes/' \
  /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo sshd -t
sudo sshd -T | grep -Ei \
  '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh.service
sudo ss -tlnp | grep sshd
```

После перезапуска `sshd` должен слушать только `0.0.0.0:2222` и `[::]:2222`. Старый оставшийся процесс на порту 22 при необходимости завершается после проверки его PID.

## 6. Правила межсетевого экрана

Политики по умолчанию:

- входящий трафик: `deny`;
- исходящий трафик: `allow`;
- маршрутизируемый трафик: `disabled`.

Итоговые правила:

- `2222/tcp` - `LIMIT IN`, SSH с ограничением частоты подключений;
- `80/tcp` - `ALLOW IN`, HTTP;
- `443/tcp` - `ALLOW IN`, HTTPS;
- журналирование: `medium`.

Команды восстановления:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw enable
sudo ufw status verbose
```

Правило для `2222/tcp` добавляется до включения UFW, иначе можно потерять SSH-доступ.

## 7. Локальное доменное имя

В `/etc/hosts` на Mac добавлена строка:

```text
192.168.56.3    devops.local
```

На сервере установлено имя `devops-vm`, а строка для `127.0.1.1` имеет вид:

```text
127.0.1.1 devops-vm.devops.local devops-vm
```

Команды:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127\.0\.1\.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

Ожидаемое полное имя: `devops-vm.devops.local`.

## 8. Снимки состояния

| Снимок | Момент создания | Состояние |
|---|---|---|
| `01-clean-install` | 08.10.2026 20:37 | Чистая установленная Ubuntu Server |
| `02-keys-configured` | 08.10.2026 21:12 | Настроены ключ и профиль SSH |
| `03-ssh-hardened` | 08.10.2026 21:26 | SSH усилен и переведён на порт 2222 |

## 9. Итоговая проверка

```bash
ssh devops
ssh -p 2222 devops@devops.local
hostname -f
sudo sshd -T | grep -Ei \
  '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
sudo ss -tlnp | grep sshd
sudo ufw status verbose
sudo bash scripts/audit.sh
echo $?
```

Ожидаемый результат аудита: все проверки `[OK]`, `не пройдено: 0`, код возврата `0`.
