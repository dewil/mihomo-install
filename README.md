# Установка Mihomo на новый сервер

## Требования

- Linux (x86_64 или arm64)
- root-доступ
- curl, python3
- systemd

## Быстрая установка

```bash
chmod +x install.sh
sudo ./install.sh
```

## Установка прямо с GitHub

```bash
wget -qO- https://raw.githubusercontent.com/dewil/mihomo-install/main/install.sh | sudo bash
```

Если ветка/путь отличается:

```bash
wget -qO- https://raw.githubusercontent.com/<owner>/<repo>/<branch>/install.sh | \
  sudo GITHUB_REPO="<owner>/<repo>" GITHUB_REF="<branch>" INSTALL_SUBDIR="" bash
```

## Что делает install.sh

1. Проверяет запуск от root
2. Скачивает бинарник mihomo v1.19.21 с GitHub
3. Создаёт системного пользователя `mihomo` (с корректным `nologin`)
4. Берёт файлы либо локально, либо скачивает их из GitHub repo
5. Копирует конфигурацию в `/etc/mihomo/`
6. Скачивает GeoIP базу (`geoip.metadb`)
7. Устанавливает скрипты сборки конфига в `/usr/local/sbin/`
8. Устанавливает systemd-сервис и cron

## Структура

```
/usr/local/bin/mihomo              — бинарник
/etc/mihomo/
  config.base.yaml                 — базовый конфиг (редактировать при необходимости)
  config.yaml                      — автогенерируемый итоговый конфиг
  subscription.url                 — URL подписки
  routing-rules.url                — URL для обновления правил маршрутизации
  routing-rules.yaml               — правила маршрутизации
  iso3166_alpha2.txt               — коды стран для алиасов
  aliases.yaml                     — автогенерируемые алиасы
  providers/vless_sub.yaml         — скачанная подписка
  geoip.metadb                     — GeoIP база
/usr/local/sbin/
  mihomo-build-config              — сборка config.yaml из подписки + правил
  mihomo-refresh                   — пересборка + hot reload без рестарта
/etc/systemd/system/mihomo.service — systemd unit
/etc/cron.d/mihomo-refresh         — cron: обновление каждую минуту
```

## Как это работает

- При старте сервиса выполняется `mihomo-build-config` (ExecStartPre), который:
  - Скачивает подписку по URL из `subscription.url`
  - Скачивает правила по URL из `routing-rules.url`
  - Генерирует `config.yaml` = `config.base.yaml` + proxy-providers/groups/rules
- Cron каждую минуту запускает `mihomo-refresh` — пересборка конфига + hot reload через REST API
- TUN-режим: mihomo создаёт интерфейс `tun0`, управляет маршрутизацией автоматически

## Настройка под новый сервер

Перед запуском можно отредактировать:

- `etc/mihomo/subscription.url` — URL подписки (при необходимости изменить)
- `etc/mihomo/config.base.yaml` — порты, DNS, исключения из маршрутизации
- `etc/mihomo/routing-rules.yaml` — правила маршрутизации трафика

Для запуска через `wget ... | bash` можно передать:

- `GITHUB_REPO` — `owner/repo`
- `GITHUB_REF` — ветка или тег (по умолчанию `main`)
- `INSTALL_SUBDIR` — подпапка установки в репозитории (по умолчанию пусто, корень репо)

## Управление

```bash
systemctl status mihomo       # статус
systemctl restart mihomo      # перезапуск
journalctl -u mihomo -f       # логи
mihomo-refresh                # ручное обновление подписки
```
