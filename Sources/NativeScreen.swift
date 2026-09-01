import AppKit
import SwiftUI

// Первый нативный экран. Растёт РЯДОМ с оболочкой над чужим сайтом, а не
// вместо неё: открывается флагом --native, обычный запуск идёт как раньше.
//
// Задача экрана не «показать заряд». Задача — проверить на живом устройстве
// то, что до сих пор было решено на бумаге: доходят ли незапрошенные кадры,
// как выглядит обрыв канала на простое, годится ли выбранная схема состояния.
//
// Про оформление. Собираемся свежим SDK при цели macOS 13 — стандартные
// контролы получают оформление системы сами, планку ради этого поднимать
// не нужно (`Notes/DECISIONS.md`). Явное «жидкое стекло» в этом SDK есть
// только двумя способами: `.buttonStyle(.glass)` в SwiftUI и AppKit-овый
// `NSGlassEffectView`; `.glassEffect` для мака в SwiftUI отсутствует.
// Оба — macOS 26, поэтому оба под проверкой доступности, а на 13 остаётся
// обычный материал.
//
// Строки интерфейса английские — как README, заметки к релизам и сам сайт,
// поверх которого приложение работало до сих пор.

// MARK: - Картинки устройств

/// Рендеры наушников берутся из копии сайта, которую приложение и так скачало
/// на машину пользователя, — в репозиторий и бандл они не входят и входить
/// не должны (`Notes/DECISIONS.md`). Отдельный слой существует ради того,
/// чтобы замена источника на свою графику не тронула ни одного экрана.
enum DeviceArtwork {
    enum Part: String { case left, right, `case`, duo }

    /// Копия может отсутствовать, файла может не быть, формат может не
    /// прочитаться — во всех трёх случаях экран обходится значком.
    static func image(_ identity: NothingCatalog.Identity, _ part: Part = .duo) -> NSImage? {
        guard let site = SiteStore.activeSite() else { return nil }
        let file = site.appendingPathComponent("assets/\(identity.artwork)_\(part.rawValue).webp")
        return NSImage(contentsOf: file)
    }
}

// MARK: - Транспорт для нативных экранов

/// Обёртка над `SerialBridge`: собирает кадры из байтов, раздаёт разобранными
/// и ведёт счётчик операций. Про экраны и хранилища не знает ничего.
final class DeviceLink: ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case ready
        case lost(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var deviceName: String?
    /// Модель и цвет. Канал опознания одноразовый — его отдаёт устройство
    /// только сразу после подключения, — поэтому берём то, что мост уже
    /// сохранил в прошлый раз. Нет кэша — нет картинки, и это не беда.
    @Published private(set) var identity: NothingCatalog.Identity?
    @Published private(set) var artwork: NSImage?

    /// Куда уходят разобранные кадры. Кого они интересуют — забота владельца:
    /// связывать транспорт с хранилищами не дело транспорта.
    var onFrame: (NothingProtocol.Frame) -> Void = { _ in }

    /// Что спросить сразу после подключения.
    var onReady: () -> Void = {}

    private let bridge = SerialBridge()
    private var operationID: UInt8 = 0

    init() {
        // Мост уже переводит свои события на главную очередь, поэтому
        // @Published здесь трогается откуда положено.
        bridge.onOpened = { [weak self] ok, reason in
            guard let self else { return }
            self.deviceName = self.bridge.deviceName
            self.resolveIdentity()
            self.status = ok ? .ready : .lost(reason)
            if ok { self.onReady() }
        }
        bridge.onReceive = { [weak self] bytes in
            // Кадр с битой контрольной суммой роняем молча: мост отдаёт байты
            // как есть, потому что чужому сайту нужно именно это.
            guard let self, let frame = try? NothingProtocol.decode(bytes) else { return }
            self.onFrame(frame)
        }
        // Мост сам переоткрывает канал, оборванный по простою, и сообщает
        // только когда восстановить не удалось.
        bridge.onClosed = { [weak self] in
            self?.status = .lost("connection lost")
        }
    }

    func connect() {
        status = .connecting
        bridge.open(uuidString: SPP_UUID)
    }

    /// Кэш опознания мост пишет по адресу устройства и только с канала
    /// опознания: на канале управления семибайтным бывает хвост кадра.
    private func resolveIdentity() {
        guard identity == nil, let address = bridge.deviceAddress,
              let hex = UserDefaults.standard.string(forKey: "fastpair-\(address)") else { return }
        guard let found = NothingCatalog.identity(fastpair: hexBytes(hex)) else { return }
        identity = found
        artwork = DeviceArtwork.image(found)
    }

    /// Устройство возвращает идентификатор операции в ответе, поэтому счётчик
    /// один на сессию.
    func nextOperationID() -> UInt8 {
        operationID &+= 1
        return operationID
    }

    func send(_ frame: [UInt8]) { bridge.write(frame) }

    /// Запрос без payload — самая частая форма.
    func request(_ command: NothingProtocol.Command) {
        send(NothingProtocol.encode(.init(command: command.rawValue,
                                          operationID: nextOperationID())))
    }
}

// MARK: - Хранилища, дроблённые по концернам

/// Заряд. Ответ `0x4007` и незапрошенный `0xE001` разбираются одинаково —
/// у донора они и вовсе идут в одну функцию.
final class BatteryStore: ObservableObject {
    @Published private(set) var readings: [NothingProtocol.Battery.Reading] = []

    func apply(_ frame: NothingProtocol.Frame) {
        guard frame.command == 0x4007 || frame.command == 0xE001,
              let battery = NothingProtocol.parseBattery(frame) else { return }
        readings = battery.readings
    }
}

/// Режим прослушивания: читается, пишется и приходит сам, когда пользователь
/// крутит ролик на самих наушниках.
final class ListeningStore: ObservableObject {
    @Published private(set) var mode: NothingProtocol.ListeningMode?
    /// Что записали и ждём подтверждения. Нужен, чтобы кнопка нажималась
    /// сразу, а не через круг «запись → подтверждение → чтение → ответ».
    @Published private(set) var pending: NothingProtocol.ListeningMode?

    private unowned let link: DeviceLink

    init(link: DeviceLink) { self.link = link }

    func set(_ mode: NothingProtocol.ListeningMode) {
        pending = mode
        link.send(NothingProtocol.encodeSetANC(mode, operationID: link.nextOperationID()))
    }

    func apply(_ frame: NothingProtocol.Frame) {
        // Подтверждение записи `0x700F` значения не несёт — оно говорит
        // «принято», а не «применено». Применённое видно только чтением.
        if frame.command == 0x700F { link.request(.anc); return }
        guard frame.command == 0x401E || frame.command == 0xE003,
              let value = NothingProtocol.parseListening(frame) else { return }
        mode = value
        pending = nil
    }
}

// MARK: - Жидкое стекло

/// Настоящее стекло там, где система его умеет, и обычный материал там, где
/// нет. В SwiftUI для мака модификатора `.glassEffect` в SDK 26.5 нет —
/// поверхность приходится брать из AppKit.
@available(macOS 26.0, *)
private struct LiquidGlass: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
    }
}

struct GlassPanel<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    init(cornerRadius: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View { content.background(surface) }

    @ViewBuilder private var surface: some View {
        if #available(macOS 26.0, *) {
            LiquidGlass(cornerRadius: cornerRadius)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

extension View {
    /// Кнопка на стекле там, где система это умеет.
    @ViewBuilder func glassy() -> some View {
        if #available(macOS 26.0, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }
}

// MARK: - Представления

// Все нижние представления принимают ЗНАЧЕНИЯ, а не хранилища: чем сделана
// реактивность, знает только контейнер. Поднимем когда-нибудь планку до
// macOS 14 с `@Observable` — поменяется он один, эти не изменятся.

private func title(_ mode: NothingProtocol.ListeningMode) -> String {
    switch mode {
    case .ancHigh:      return "High"
    case .ancMid:       return "Mid"
    case .ancLow:       return "Low"
    case .ancAdaptive:  return "Adaptive"
    case .off:          return "Off"
    case .transparency: return "Transparency"
    }
}

/// Пояснение под переключателем: у Nothing одно значение кодирует и режим,
/// и силу шумоподавления, и по названию это не очевидно.
private func caption(_ mode: NothingProtocol.ListeningMode) -> String {
    switch mode {
    case .ancHigh:      return "Noise cancellation at full strength."
    case .ancMid:       return "Noise cancellation, medium strength."
    case .ancLow:       return "Noise cancellation, light strength."
    case .ancAdaptive:  return "Strength follows the noise around you."
    case .off:          return "No processing — passive isolation only."
    case .transparency: return "Outside sound is passed through."
    }
}

private func title(_ component: NothingProtocol.Battery.Component) -> String {
    switch component {
    case .left:   return "Left"
    case .right:  return "Right"
    case .case:   return "Case"
    case .stereo: return "Headphones"
    }
}

struct ConnectionBadge: View {
    let status: DeviceLink.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(text)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var colour: Color {
        switch status {
        case .ready:      return .green
        case .connecting: return .orange
        case .idle:       return .secondary
        case .lost:       return .red
        }
    }

    private var text: String {
        switch status {
        case .idle:             return "Not connected"
        case .connecting:       return "Connecting…"
        case .ready:            return "Connected"
        case .lost(let reason): return reason
        }
    }
}

/// Портрет устройства. Рендеры лежат на прозрачном фоне, и чёрные наушники
/// на тёмной теме сливались бы с ней — поэтому под картинкой семантическая
/// подложка: она сама светлеет и темнеет вместе с системой, в отличие от
/// любого подобранного цвета.
struct DevicePortrait: View {
    let artwork: NSImage?

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                // Копии сайта нет или устройство не опознано — значок честнее
                // пустого места.
                Image(systemName: "headphones")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
    }
}

struct DeviceHeader: View {
    let name: String?
    let status: DeviceLink.Status
    let charge: NothingProtocol.Battery.Reading?
    let artwork: NSImage?
    let reconnect: () -> Void

    var body: some View {
        GlassPanel {
            HStack(spacing: 14) {
                DevicePortrait(artwork: artwork)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? "Nothing device")
                        .font(.title3.weight(.semibold))
                    ConnectionBadge(status: status)
                }
                Spacer(minLength: 12)
                if let charge {
                    HStack(spacing: 5) {
                        if charge.charging {
                            Image(systemName: "bolt.fill").foregroundStyle(.green)
                        }
                        Text("\(charge.percent)%")
                            .font(.title3.weight(.medium).monospacedDigit())
                    }
                }
                if case .lost = status {
                    Button("Reconnect", action: reconnect).glassy()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }
}

struct BatterySection: View {
    let readings: [NothingProtocol.Battery.Reading]

    var body: some View {
        Section("Battery") {
            if readings.isEmpty {
                Text("No reading yet").foregroundStyle(.secondary)
            } else {
                ForEach(readings, id: \.component) { reading in
                    LabeledContent(title(reading.component)) {
                        HStack(spacing: 10) {
                            Gauge(value: Double(reading.percent), in: 0...100) { EmptyView() }
                                .gaugeStyle(.linearCapacity)
                                .frame(width: 130)
                            Text("\(reading.percent)%")
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

struct ListeningSection: View {
    let mode: NothingProtocol.ListeningMode?
    let pending: NothingProtocol.ListeningMode?
    let enabled: Bool
    let select: (NothingProtocol.ListeningMode) -> Void

    var body: some View {
        Section("Listening mode") {
            // Выбор необязательный: пока устройство не ответило, не выбрано
            // ничего — честнее, чем показать «Off» до первого чтения.
            Picker("Mode", selection: Binding<NothingProtocol.ListeningMode?>(
                get: { pending ?? mode },
                set: { if let value = $0 { select(value) } })) {
                ForEach(NothingProtocol.ListeningMode.allCases, id: \.self) { value in
                    Text(title(value)).tag(Optional(value))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!enabled)

            if let shown = pending ?? mode {
                HStack(spacing: 6) {
                    Text(caption(shown))
                    if pending != nil && pending != mode {
                        Text("· applying…")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct DeviceScreen: View {
    @ObservedObject var link: DeviceLink
    @ObservedObject var battery: BatteryStore
    @ObservedObject var listening: ListeningStore
    let reconnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DeviceHeader(name: link.deviceName,
                         status: link.status,
                         charge: battery.readings.first,
                         artwork: link.artwork,
                         reconnect: reconnect)
                // Сверху оставлено под полосу заголовка: она прозрачная,
                // и контент уходит под кнопки окна.
                .padding(.top, 34)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            Form {
                BatterySection(readings: battery.readings)
                ListeningSection(mode: listening.mode,
                                 pending: listening.pending,
                                 enabled: link.status == .ready,
                                 select: listening.set)
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 620, minHeight: 460)
    }
}

// MARK: - Окно

/// Единственное место, где известно, что реактивность сделана на
/// `ObservableObject`, и единственное, что связывает транспорт с хранилищами.
final class NativeWindow {
    private let window: NSWindow
    private let link = DeviceLink()
    private let battery = BatteryStore()
    private let listening: ListeningStore

    init() {
        listening = ListeningStore(link: link)

        link.onFrame = { [battery, listening] frame in
            battery.apply(frame)
            listening.apply(frame)
        }
        link.onReady = { [weak link] in
            link?.request(.battery)
            link?.request(.anc)
        }

        // Окно создаём до содержимого — та же грабля, что с WKWebView.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                      .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Nothing"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.contentView = NSHostingView(
            rootView: DeviceScreen(link: link, battery: battery, listening: listening,
                                   reconnect: { [weak link] in link?.connect() }))
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        link.connect()
    }
}
