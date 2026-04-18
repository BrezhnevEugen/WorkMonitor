# Разработка Work Monitor

Техническое описание для тех, кто собирает из исходников, расширяет приложение или исправляет баги. Пользовательский README — в [README.md](./README.md), история изменений — в [CHANGELOG.md](./CHANGELOG.md).

## Стек

- Swift 5.9, macOS 13+ (`platforms: [.macOS(.v13)]` в `Package.swift`).
- UI — SwiftUI + AppKit (для `NSStatusItem`, `NSPopover`, `NSHostingController`).
- Сборка — Swift Package Manager. Без Xcode-проекта: `swift build` + `build.sh`, который собирает `.app`-бандл вручную.
- Данные — парсинг вывода системных утилит (`lsof`, `vm_stat`, `sysctl`, `top`, `df`, `netstat`, `docker ps`).
- Персистентность настроек — `UserDefaults`.
- Тесты — XCTest.

Внешних Swift-пакетов нет — всё на stdlib + Foundation + AppKit/SwiftUI.

## Структура проекта

```
WorkMonitor/                              корень Swift-пакета
├── Package.swift                         два таргета: исполняемый + ядро + тесты
├── build.sh                              swift build → упаковка в WorkMonitor.app
├── build-dmg.sh                          build.sh → codesign → DMG → notarize → staple
├── README.md                             user-facing документация
├── CHANGELOG.md                          история версий
├── DEVELOPMENT.md                        этот файл
│
├── WorkMonitor/                          UI-модуль (executable target)
│   ├── WorkMonitorApp.swift              @main, NSApplicationDelegateAdaptor
│   ├── AppDelegate.swift                 NSStatusItem + NSPopover, таймеры, трей-иконка
│   ├── SystemMonitor.swift               ObservableObject со всей живой телеметрией
│   ├── DashboardView.swift               SwiftUI popover (header/summary/секции/footer/about/settings)
│   ├── Theme.swift                       ThemePalette, ThemeKind, ThemeManager
│   ├── AppSettings.swift                 пользовательские флаги (видимость секций, группировка)
│   ├── LocalizationManager.swift         i18n через .lproj-бандлы + форматы единиц
│   ├── ProcessesPanel.swift              отдельная NSPanel с деталями процессов (legacy, не вызывается)
│   ├── Info.plist                        LSUIElement=YES, версия, min system
│   ├── WorkMonitor.entitlements          network.client, app-sandbox=NO
│   └── Resources/
│       ├── en.lproj/Localizable.strings
│       └── ru.lproj/Localizable.strings
│
├── WorkMonitorCore/                      чистая логика без UI-зависимостей
│   └── Sources/WorkMonitorCore/
│       ├── Models.swift                  PortInfo, DockerContainer, MemoryInfo,
│       │                                 CPUInfo, DiskInfo, NetworkInfo, ProcessMemoryInfo
│       └── MonitoringParsers.swift       LsofListenOutputParser, DockerPsOutputParser,
│                                         MemoryOutputParser, ProcessPsOutputParser,
│                                         TopCPUOutputParser, DfOutputParser,
│                                         NetstatOutputParser, HTMLTitleParser
│
└── Tests/WorkMonitorCoreTests/           XCTest, по файлу на парсер
    ├── LsofParserTests.swift
    ├── DockerParserTests.swift
    ├── MemoryParserTests.swift
    ├── ProcessPsParserTests.swift
    ├── HTMLTitleParserTests.swift
    └── CPUDiskNetParserTests.swift
```

Причина разделения на два модуля: `WorkMonitorCore` не зависит от AppKit/SwiftUI, поэтому его можно гонять в тестах без `NSApplication` и без доступа к реальной системе — в тесты подаются фейковые строки (примеры `vm_stat`, `lsof` и т. д.), проверяется парсер. UI-слой изолирован от форматов вывода системных утилит.

## Поток данных

```
macOS                     WorkMonitorCore (чистая логика)              UI
───────                   ─────────────────────────────────             ───────
lsof -iTCP ──────┐        ┌──► LsofListenOutputParser  ──► [PortInfo]
docker ps  ──────┤        ├──► DockerPsOutputParser   ──► [Container]
vm_stat    ──────┤        ├──► MemoryOutputParser     ──► MemoryInfo
sysctl     ──────┤  Shell ├──►                                            DashboardView
top        ──────┼──► SystemMonitor ──► TopCPUOutputParser ──► CPUInfo  ─┼─► Header
df         ──────┤        ├──► DfOutputParser         ──► DiskInfo       │  SummaryBar
netstat    ──────┤        ├──► NetstatOutputParser    ──► NetworkInfo    │  PortsSection
ps         ──────┘        └──► ProcessPsOutputParser  ──► [Process]      │  DockerSection
                                                                          │  ProcessesSection
                              @Published поля                             └─► Footer
                              ObservableObject
```

**`SystemMonitor.refresh()`** — единственная точка, где запускается live-опрос. Внутри — 7 параллельных `async let` шелл-вызовов, каждый возвращает строку, строка уходит в соответствующий парсер из `WorkMonitorCore`, результат пишется в `@Published`-поле. После обновления портов делается HTTP-пробы на `localhost:<port>` в `withTaskGroup` — если отвечает и `Content-Type: text/html`, парсится `<title>` и в строке порта появляется кнопка «open».

Для сети `NetstatOutputParser.parseTotals` возвращает cumulative счётчики байт. Скорость — дельта между сэмплами, делённая на прошедшее время (`SystemMonitor.lastNetTotals`). Первый сэмпл после старта даёт `0 B/s`, начиная со второго — реальная скорость.

## Таймеры

Два в `AppDelegate`:

- `popoverTimer` (2 секунды) — запускается при открытии popover, останавливается при закрытии. Именно его видно как `live · 2s` в футере.
- `backgroundTimer` (15 секунд) — работает всё время жизни приложения. Нужен чтобы трей-иконка и её счётчик отражали актуальное состояние. Фоновой частоты достаточно: все вызовы (`lsof`, `docker ps`, `top`, `df`, `netstat`, `vm_stat`) суммарно выполняются менее чем за 100 мс на типичной dev-машине.

Обе частоты зафиксированы в `AppDelegate.applicationDidFinishLaunching` и `openPopover`. Если захочется сделать их настраиваемыми — добавить поля в `AppSettings` и использовать в конструкторах таймеров.

## Архитектура UI

### Корневые view'ы и navigation

`DashboardView` — единственный хост popover'а. Внутри — три «страницы», переключаются через локальный `@State route: Route`:

```swift
enum Route { case main, about, settings }
```

Переходы через `go(_ r: Route)` с `withAnimation(.easeInOut(duration: 0.15))` для opacity-транзишена. `AboutView` и `SettingsView` — отдельные структуры, обе берут `onBack: () -> Void` в конструкторе.

### Environment objects

Три `ObservableObject`-синглтона пробрасываются через environment из `AppDelegate.applicationDidFinishLaunching`:

```swift
popover.contentViewController = NSHostingController(
    rootView: DashboardView(monitor: monitor)
        .environmentObject(LocalizationManager.shared)
        .environmentObject(AppSettings.shared)
        .environmentObject(ThemeManager.shared)
)
```

Любой view получает их через `@EnvironmentObject private var loc: LocalizationManager` и аналогично — SwiftUI автоматически подписывает view на `@Published`-изменения и перерисовывает тело при публикации.

**Важно:** не используйте `@ObservedObject private var m = Singleton.shared` — паттерн ломается при пересоздании view-структуры (SwiftUI может сбросить подписку). Всегда прокидывайте через environment. Этот баг был в v2.0 и чинился переходом на `@EnvironmentObject`.

### Система тем

В `Theme.swift`:

- `ThemePalette` — плоский `struct` с ~16 цветами + `colorScheme: ColorScheme`.
- `ThemeKind` — `enum` вариантов (`.auto`, `.darkTerminal`, `.lightMinimal`, `.midnightBlue`). Метод `resolvedPalette()` возвращает палитру; для `.auto` — смотрит `NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])`.
- `ThemeManager` — `ObservableObject`-синглтон, хранит текущий `kind`, персистит в `UserDefaults[WorkMonitor.themeKind]`. В `init` подписывается на `DistributedNotificationCenter` с именем `AppleInterfaceThemeChangedNotification` — это стандартное macOS-уведомление при смене системной темы. Когда оно приходит и текущая тема `.auto`, вызывает `objectWillChange.send()` → подписанные view'ы перерисовываются.
- `Theme` — фасад со статическими computed property'ями, которые читают из `ThemeManager.shared.palette`. Вид кода в view'ах не меняется (`Theme.bgPopover`, `Theme.accent`), но значения обновляются при смене темы.

Фонты не зависят от темы и хранятся как статические константы (`Theme.body`, `Theme.title`, `Theme.mono(_:weight:)`).

### Hover-паттерн

Строки в секциях показывают кнопки действий только на hover. Реализация — локальный `@State hovering` в каждой строке + `RevealOnRowHover(hovering:)` (модификатор из `Theme.swift`), который переключает opacity 0↔1 с анимацией 0.1 с. Row-background — `hovering ? Theme.bgRowHover : Color.clear` через `RoundedRectangle`.

### Live-индикатор в футере

Простейший `@State blink` + `.animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: blink)`, запускается в `onAppear`. Никаких Combine-таймеров, только SwiftUI.

## Локализация

Ключ → перевод. Функция — `LocalizationManager.shared.tr(_ key: String)`, резолвит через `NSLocalizedString` с бандлом, выбранным по `AppLanguage` (`system` / `english` / `russian`). Выбор хранится в `UserDefaults[WorkMonitor.appLanguage]`.

Файлы переводов — `Resources/{en,ru}.lproj/Localizable.strings`. Бандл на уровне рантайма — `Contents/Resources/{en,ru}.lproj` (копируются в `build.sh`). Без этой копии `NSLocalizedString` не найдёт файл.

Форматирование чисел: `formatGigabytesOneDecimal`, `formatRamUsedTotalLine`, `formatSwapUsedTotalLine`, `formatMegabytesOrGigabytes`, `formatNetworkRate`, `formatRelativeUpdated`. Единицы (`GB`/`ГБ`, `MB`/`МБ`) подбираются по `useRussianStyleUnits` — учитывает и явный выбор языка, и системный `Locale.preferredLanguages`.

## Настройки (`AppSettings`)

Три boolean-флага с `UserDefaults`-персистентностью:

- `showPorts`, `showDocker`, `showProcesses` — видимость одноимённых секций; `DashboardView.mainView` рендерит их под условием.
- `groupPortsByApp` — переключает между плоским списком `PortRow` и подгруппами `PortAppGroupView` внутри `PortsSection`.

Все флаги — `@Published`, так что UI перерисовывается мгновенно.

Добавляя новый флаг:

1. В `AppSettings.swift` — новый `keyXxx`, `@Published var xxx`, и строчка в `init`.
2. В `SettingsView` — добавить `CheckboxRow` внутри подходящей `SettingsGroup`.
3. В `Localizable.strings` — ключ метки.
4. В месте использования — читать `settings.xxx`.

## Трей-иконка

В `AppDelegate.updateTrayLabel()`. Состояние кодируется формой SF-символа, не цветом:

| условие | символ | semantics |
|---|---|---|
| `memPct > 90` или (`!dockerAvailable && portCount == 0`) | `exclamationmark.circle.fill` | critical |
| `memPct > 75` или unhealthy-контейнер | `exclamationmark.triangle.fill` | warning |
| `portCount == 0` | `circle` | idle |
| иначе | `circle.fill` | нормально |

Символ создаётся через `NSImage(systemSymbolName:…).withSymbolConfiguration(…)` с `isTemplate = true` — macOS сам подкрашивает под фон строки меню (белая на тёмной, чёрная на светлой).

Счётчик портов показывается текстом рядом с иконкой в `NSColor.labelColor` (тоже адаптивный). При `portCount == 0` — текст пустой, остаётся только значок.

Подписка на обновления — Combine-sink на `monitor.$ports.combineLatest($memory, $dockerAvailable, $containers)` в `applicationDidFinishLaunching`.

## Сборка

### `build.sh`

1. `swift build -c release` — бинарник в `.build/release/WorkMonitor`.
2. Создаёт `WorkMonitor.app/Contents/{MacOS, Resources}`.
3. Копирует бинарник, `Info.plist`, `en.lproj` и `ru.lproj`.
4. Если в env задан `CODESIGN_IDENTITY` — подписывает с hardened runtime и entitlements.

### `build-dmg.sh`

Обёртка: `./build.sh` → codesign → упаковка в UDZO `.dmg` через `hdiutil` → опциональная нотаризация через `xcrun notarytool` (три способа, описаны в комментарии в начале скрипта) → staple.

### Entitlements

`WorkMonitor/WorkMonitor.entitlements`:

```xml
com.apple.security.app-sandbox        false
com.apple.security.network.client     true
```

Сэндбокс отключён сознательно: приложению нужно запускать `lsof`, `docker`, `ps` — это невозможно в sandboxed-режиме. `network.client` — для HTTP-проб на `localhost:<port>`.

## Тестирование

`swift test` — гоняет все тесты в `Tests/WorkMonitorCoreTests`. Таргет `WorkMonitorCoreTests` зависит только от `WorkMonitorCore`, без UI.

Паттерн тестов: подаётся кусок сырого вывода утилиты (скопированный из реального `vm_stat`, `lsof -iTCP` и т. д.), проверяется что парсер вытаскивает ожидаемые поля. Пример — `CPUDiskNetParserTests.testParseCPUStandardMacOSHeader`.

Запуск отдельного теста:

```bash
swift test --filter CPUDiskNetParserTests.testParseDfRoot
```

## Как расширять

### Добавить новую метрику в SummaryBar

1. В `Models.swift` добавить `struct XxxInfo: Equatable` c `.zero` и нужными accessor'ами.
2. В `MonitoringParsers.swift` — `enum XxxOutputParser { public static func parse(...) }`. Добавить XCTest.
3. В `SystemMonitor.swift` — `@Published var xxx: XxxInfo = .zero`, `fetchXxx()` и вызов в `refresh()`.
4. В `DashboardView.SummaryBar` — добавить `MetricCell` (четыре помещается впритык, для пяти придётся пересобрать layout).
5. Локализация: ключ `metric_xxx`.

### Добавить тему

1. В `Theme.swift → ThemeKind` — новый `case`, `titleKey: "theme_xxx"`, палитра в `explicitPalette`.
2. `Localizable.strings` (ru/en) — ключ `theme_xxx`.
3. Ничего больше: picker автоматически подхватывает все `ThemeKind.allCases`.

### Добавить секцию в popover

1. Новая view в `DashboardView.swift`, обёрнутая в `CollapsibleSection(title:count:)`.
2. Если секция ходит за данными — добавить `@Published`-поле в `SystemMonitor`.
3. Под условием в `DashboardView.mainView` + чекбокс в `SettingsView` и флаг в `AppSettings` (если хочется давать скрывать).
4. Локализация: ключ `section_xxx`.

### Добавить команду (Docker start/stop/logs)

Сейчас кнопки `start`/`stop`/`logs` в `DockerRow` — заглушки. Чтобы заработали:

1. В `SystemMonitor` добавить метод вида `runDocker(_ args: [String])` через существующий `Self.shell(_:args:)`.
2. Передать колбэк в `DockerRow` (либо прокинуть `monitor` через `@EnvironmentObject` — тогда `SystemMonitor` тоже надо делать environment object).
3. Для `logs` — либо открыть новое окно с `NSTextView` + поток `docker logs -f <id>`, либо открыть Terminal с командой. Проще второе.

### Добавить локализованный ключ

1. Ключ в обоих `ru.lproj/Localizable.strings` и `en.lproj/Localizable.strings`.
2. В коде — `loc.tr("your_key")`.
3. Быстрая проверка целостности: скрипт снизу должен вывести пусто на обе секции.

```bash
grep -hoE '\btr\("[a-z_0-9]+"\)' WorkMonitor/*.swift | grep -oE '"[a-z_0-9]+"' | sort -u > /tmp/used.txt
grep -oE '^"[a-z_0-9]+"' WorkMonitor/Resources/ru.lproj/Localizable.strings | sort -u > /tmp/ru.txt
grep -oE '^"[a-z_0-9]+"' WorkMonitor/Resources/en.lproj/Localizable.strings | sort -u > /tmp/en.txt
echo "missing ru:"; comm -23 /tmp/used.txt /tmp/ru.txt
echo "missing en:"; comm -23 /tmp/used.txt /tmp/en.txt
```

## Известные ограничения и TODO

- Кнопки `stop`/`start`/`logs` в Docker-секции — UI-заглушки, без реального исполнения.
- `⚙ Settings → Система` открывает только системный экран Login Items, сам автозапуск приложение не регистрирует (нужно добавить `ServiceManagement.SMAppService.mainApp.register()` для macOS 13+).
- Скорость сети считается по `netstat -ibn` — достаточно точна для визуального индикатора, но на очень коротких интервалах (< 1 с) может скакать.
- `ProcessesPanel.swift` — legacy-код от v1, сейчас не вызывается из AppDelegate. Компилируется, но не показывается. Можно удалить, если не планируется возврат детального экрана процессов.
- Частоты обновления (2 с / 15 с) зашиты в код, не настраиваются из UI.
- Нет UI-интеграционных тестов — только parser-level XCTest. Для SwiftUI-тестов нужен отдельный UI-тест-таргет.

## Отладка

- Приложение не показывается в Dock (`LSUIElement = YES`). Для приложения с Dock-иконкой временно поменять `LSUIElement` на `false` в `Info.plist` и пересобрать.
- Логи шелл-вызовов не пишутся — в `SystemMonitor.shell(_:args:)` можно временно добавить `print(command, args, "→", output.count, "bytes")`.
- Для отладки именно SwiftUI-rerender'ов полезен `Self._printChanges()` в body view (есть в iOS/macOS-16 runtime).
- NSPopover и hosting view дебажатся сложно — при изменении layout'а проще пересобирать и смотреть вживую, чем гадать.

## Релиз

1. Обновить `CFBundleShortVersionString` и `CFBundleVersion` в `WorkMonitor/Info.plist`.
2. Обновить `CHANGELOG.md` (новая секция сверху по формату Keep a Changelog).
3. Проверить README, если есть user-facing изменения.
4. `./build-dmg.sh` с заданными `CODESIGN_IDENTITY` и `NOTARY_KEYCHAIN_PROFILE` / альтернативными переменными.
5. Убедиться что `codesign --verify WorkMonitor.app` не ругается.
6. Залить DMG в GitHub Release, добавить release notes из CHANGELOG.
