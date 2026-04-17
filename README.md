# Work Monitor

Утилита для **macOS 13+** в виде приложения только в **меню-баре**: порты, Docker, память и топ процессов — в одном окне из статус-бара, без отдельного окна в Dock.

Репозиторий: [github.com/BrezhnevEugen/WorkMonitor](https://github.com/BrezhnevEugen/WorkMonitor)

## Возможности

- **Память** — использование RAM, swap, давление, разбивка (apps / wired / compressed); кнопка **Processes** открывает панель с топом по RSS и завершением пользовательских процессов.
- **Порты** — слушающие TCP (`lsof`), группировка по процессу; эвристика веб-интерфейса по `http://localhost:PORT`.
- **Docker** — `docker ps -a` (статусы, образы, порты), если CLI доступен.
- **About** — описание и ссылка на поддержку [Boosty](https://boosty.to/genius_me/donate).

## Расположение кода

Исходники Swift Package Manager и приложение:

```text
work monitor/WorkMonitor/
  Package.swift
  WorkMonitor/              # исполняемый таргет (SwiftUI + AppKit)
  WorkMonitorCore/          # модели и парсеры вывода CLI
  Tests/WorkMonitorCoreTests/
```

## Сборка

Из каталога пакета:

```bash
cd "work monitor/WorkMonitor"
swift build -c release
```

Сборка **`.app`** (скрипт копирует бинарь и `Info.plist`):

```bash
./build.sh
open WorkMonitor.app
```

## Тесты

Юнит-тесты парсеров (`lsof`, Docker format, память, `ps`, HTML title):

```bash
cd "work monitor/WorkMonitor"
swift test
```

В репозитории настроен GitHub Actions: [`.github/workflows/swift-tests.yml`](.github/workflows/swift-tests.yml) — `swift test -c release` на `macos-14`.

## Git-хуки

После `git clone` один раз:

```bash
./scripts/install-git-hooks.sh
```

Хук `commit-msg` убирает служебную строку `Made-with: Cursor` из сообщения коммита.

## Требования

- macOS **13** или новее  
- Xcode / Swift **5.9** (или toolchain с поддержкой пакета)

## Лицензия

См. файл [LICENSE](LICENSE) в корне репозитория.
