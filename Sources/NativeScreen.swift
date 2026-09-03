import AppKit
import Combine
import SwiftUI

// Нативный экран приложения. С 02.09.2026 он основной: обычный запуск идёт
// сюда, а чужой сайт остался под флагом --web, потому что умеет то, до чего
// этот экран пока не дорос — пространственный звук, две пары, детекция в ухе,
// кодек, персональный звук (`Notes/DECISIONS.md`).
//
// Про оформление. Собираемся свежим SDK при цели macOS 13 — стандартные
// контролы получают оформление системы сами, планку ради этого поднимать
// не нужно (`Notes/DECISIONS.md`). Явное «жидкое стекло» в этом SDK есть
// только двумя способами: `.buttonStyle(.glass)` в SwiftUI и AppKit-овый
// `NSGlassEffectView`; `.glassEffect` для мака в SwiftUI отсутствует.
// Оба — macOS 26, поэтому оба под проверкой доступности, а на 13 остаётся
// обычный материал.
//
// Строки интерфейса переводятся: русский и английский, таблицей в коде и с
// переключением на лету — `Sources/Localisation.swift`. Всё, что попадает на
// экран, обёрнуто в `t(...)`; ключ — английская строка.

// MARK: - Тема оформления

/// Тема окна. `system` — идти за системой, то есть не навязывать ничего:
/// `NSApp.appearance = nil` и есть «как в системе».
enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    var title: String {
        switch self {
        case .system: return t("System")
        case .light:  return t("Light")
        case .dark:   return t("Dark")
        }
    }
}

/// Выбор темы переживает перезапуск: хранится в `UserDefaults` рядом с языком.
final class Appearance: ObservableObject {
    static let shared = Appearance()

    private static let key = "interface-theme"

    @Published var theme: Theme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
            apply()
        }
    }

    private init() {
        theme = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(Theme.init(rawValue:)) ?? .system
    }

    /// Применить сохранённое. Зовётся на старте — до разбора отладочных
    /// флагов `--dark` и `--light`, чтобы флаг оставался сильнее настройки.
    func apply() { NSApp.appearance = theme.appearance }
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
    /// Доходили ли до готовности хоть раз. Обрыв на простое — штатное дело,
    /// и выдёргивать из-под пользователя весь экран ради него нельзя:
    /// стартовый экран показывается только пока связи не было ни разу.
    @Published private(set) var everConnected = false
    @Published private(set) var deviceName: String?
    /// Модель и цвет. Канал опознания одноразовый — его отдаёт устройство
    /// только сразу после подключения, — поэтому берём то, что мост уже
    /// сохранил в прошлый раз. Нет кэша — нет картинки, и это не беда.
    @Published private(set) var identity: NothingCatalog.Identity?
    /// Версия прошивки. Нужна не столько экрану, сколько каталогу: полосы
    /// возможностей и раскладок жестов выбираются по ней.
    @Published private(set) var firmware: String?

    /// Куда уходят разобранные кадры. Кого они интересуют — забота владельца:
    /// связывать транспорт с хранилищами не дело транспорта.
    var onFrame: (NothingProtocol.Frame) -> Void = { _ in }

    /// Что спросить сразу после подключения.
    var onReady: () -> Void = {}

    /// Прошивка прочитана — с этого момента каталог может сказать, какие
    /// команды устройству вообще имеет смысл слать.
    var onFirmware: (String) -> Void = { _ in }

    /// Связь потеряна насовсем. Нужно тем, кто держит состояние, которого
    /// на устройстве не спросить, — например поиску: он звенит, а сказать
    /// ему «замолчи» уже нечем.
    var onLost: () -> Void = {}

    private let bridge = SerialBridge()
    private var operationID: UInt8 = 0

    /// Подключение идёт в две фазы, как у сайта: сначала канал опознания —
    /// устройство отдаёт 7 байт с моделью только там и только сразу после
    /// открытия, — потом канал управления. Кэширует опознание сам мост;
    /// наша забота — вовремя перейти ко второй фазе.
    private enum Phase { case identifying, control }
    private var phase: Phase = .control

    init() {
        // Мост уже переводит свои события на главную очередь, поэтому
        // @Published здесь трогается откуда положено.
        bridge.onOpened = { [weak self] ok, reason in
            guard let self else { return }
            if self.phase == .identifying {
                // Открылся — ждём байты опознания (или подставленный мостом
                // кэш) в onReceive. Не открылся — идём на канал управления
                // как раньше: без модели, со значком вместо рендера.
                if !ok { self.startControl() }
                return
            }
            self.deviceName = self.bridge.deviceName
            self.resolveIdentity()
            self.status = ok ? .ready : .lost(reason)
            if ok { self.everConnected = true; self.onReady() }
        }
        bridge.onReceive = { [weak self] bytes in
            guard let self else { return }
            // Байты опознания — не кадр нашего протокола: мост уже сохранил
            // их в кэш по адресу устройства, дальше они не нужны. Переходим
            // строго по семи байтам — столько в анонсе и в подставленном
            // кэше; огрызок от склейки RFCOMM фазу не обрывает, его
            // дождётся таймер.
            if self.phase == .identifying {
                if bytes.count == 7 { self.startControl() }
                return
            }
            // Кадр с битой контрольной суммой роняем молча: мост отдаёт байты
            // как есть, потому что чужому сайту нужно именно это.
            guard let frame = try? NothingProtocol.decode(bytes) else { return }
            // Прошивку транспорт забирает себе: это метаданные устройства,
            // того же рода, что имя и опознание. Кадр при этом уходит дальше.
            if frame.command == 0x4042, let version = NothingProtocol.parseFirmware(frame) {
                self.firmware = version
                self.onFirmware(version)
            }
            self.onFrame(frame)
        }
        // Мост сам переоткрывает канал, оборванный по простою, и сообщает
        // только когда восстановить не удалось.
        bridge.onClosed = { [weak self] in
            self?.status = .lost("connection lost")
            self?.onLost()
        }
        // А когда удалось — переспрашиваем всё заново. Молчаливое
        // восстановление правильно для сайта и неверно для нас: после
        // перезагрузки наушников их состояние могло измениться целиком,
        // и показывать прежнее как настоящее было бы враньём.
        bridge.onRestored = { [weak self] in
            guard let self else { return }
            self.status = .ready
            self.onReady()
        }
    }

    /// Счётчик попыток подключения. Таймер ниже держит своё значение и
    /// чужую попытку не трогает — иначе Reconnect в первые шесть секунд
    /// после предыдущего подключения обрезал бы новое опознание досрочно.
    /// Мост ту же гонку у себя закрывает счётчиком generation.
    private var attempt = 0

    func connect() {
        status = .connecting
        phase = .identifying
        attempt += 1
        let mine = attempt
        bridge.close()
        bridge.open(uuidString: FASTPAIR_UUID)
        // Открытый, но молчащий канал опознания подстраховкой моста не
        // покрыт — она срабатывает, только если канал не открылся вовсе.
        // Свой таймер переводит на управление в любом случае: опознание
        // подождёт до следующего раза, кэш переживает перезапуски.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            guard let self, self.attempt == mine else { return }
            self.startControl()
        }
    }

    /// Вторая фаза: канал опознания закрывается, открывается управление.
    private func startControl() {
        guard phase == .identifying else { return }
        phase = .control
        bridge.close()
        bridge.open(uuidString: SPP_UUID)
        // Канал бывает найден, открыт асинхронно — и не открыт никогда:
        // `rfcommChannelOpenComplete` тогда не зовётся вовсе, и своего
        // таймаута у моста для этого случая нет. Так выглядит занятый канал
        // (устройство отдаёт его одной программе за раз) — на этом уже
        // молча зависал и инструмент сверки. Без таймера экран крутил бы
        // «Ищу наушники…» бесконечно, вместо того чтобы дать переподключить.
        let mine = attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
            guard let self, self.attempt == mine, self.status == .connecting else { return }
            self.status = .lost("the connection is busy or the device is not responding")
        }
    }

    /// Кэш опознания мост пишет по адресу устройства и только с канала
    /// опознания: на канале управления семибайтным бывает хвост кадра.
    private func resolveIdentity() {
        guard identity == nil, let address = bridge.deviceAddress,
              let hex = UserDefaults.standard.string(forKey: "fastpair-\(address)") else { return }
        guard let found = NothingCatalog.identity(fastpair: hexBytes(hex)) else { return }
        identity = found
    }

    /// Устройство возвращает идентификатор операции в ответе, поэтому счётчик
    /// один на сессию.
    func nextOperationID() -> UInt8 {
        operationID &+= 1
        return operationID
    }

    func send(_ frame: [UInt8]) { bridge.write(frame) }

    /// Отпустить канал. Устройство отдаёт его одной программе за раз, поэтому
    /// пока мы его держим, к наушникам не подключится больше никто.
    func close() { bridge.close() }

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
    /// Ступени силы и наличие прозрачности у этой модели; наполняется
    /// владельцем, когда известны модель и прошивка.
    @Published var strengths: [NothingProtocol.NoiseStrength] = []
    @Published var hasTransparency = true

    /// Последняя виденная сила. Нужна, когда пользователь уходит на
    /// прозрачность и возвращается: сила на проводе слита с режимом, и без
    /// этой памяти пришлось бы выдумывать её за него — ровно как с составом
    /// круга у жестов.
    private var lastStrength: NothingProtocol.NoiseStrength = .high

    private unowned let link: DeviceLink

    init(link: DeviceLink) { self.link = link }

    func set(_ mode: NothingProtocol.ListeningMode) {
        pending = mode
        link.send(NothingProtocol.encodeSetANC(mode, operationID: link.nextOperationID()))
    }

    /// Сменить вид обработки, сохранив силу: возвращаясь к шумоподавлению,
    /// человек ожидает ту силу, на которой был.
    func set(noise: NothingProtocol.NoiseMode) {
        set(.init(noise: noise, strength: strengths.contains(lastStrength)
                                          ? lastStrength : (strengths.last ?? .high)))
    }

    func set(strength: NothingProtocol.NoiseStrength) {
        set(.init(noise: .cancelling, strength: strength))
    }

    func apply(_ frame: NothingProtocol.Frame) {
        // Подтверждение записи `0x700F` значения не несёт — оно говорит
        // «принято», а не «применено». Применённое видно только чтением.
        if frame.command == 0x700F { link.request(.anc); return }
        guard frame.command == 0x401E || frame.command == 0xE003,
              let value = NothingProtocol.parseListening(frame) else { return }
        mode = value
        if let strength = value.strength { lastStrength = strength }
        pending = nil
    }
}

/// Звук: пресет эквалайзера, продвинутый эквалайзер, усиление баса и
/// пространственный звук. Четыре поля в одном хранилище не случайно — они
/// гейтят друг друга: активный продвинутый эквалайзер снимает выбор с
/// пресетов, а у моделей с флагом mutuallyExclusive бас несовместим с
/// пространственным звуком.
final class SoundStore: ObservableObject {
    @Published private(set) var preset: NothingProtocol.EqualiserPreset?
    @Published private(set) var pendingPreset: NothingProtocol.EqualiserPreset?
    /// Продвинутый эквалайзер активен: пресеты в этот момент не действуют,
    /// и показывать один из них выбранным было бы враньём.
    @Published private(set) var advancedOn = false
    /// nil — устройство ещё не ответило (или команда ему недоступна);
    /// секция баса в этом случае не показывается вовсе.
    @Published private(set) var bass: (enabled: Bool, level: Int)?
    @Published private(set) var pendingBass: (enabled: Bool, level: Int)?
    /// Пространственный звук — режим, а не признак: «следит за головой» это
    /// тот же первый режим со вторым байтом, и булевым его не выразить.
    @Published private(set) var spatial: NothingProtocol.SpatialMode?
    @Published private(set) var pendingSpatial: NothingProtocol.SpatialMode?
    /// Режимы, доступные модели; наполняется владельцем по каталогу.
    @Published var spatialModes: [NothingProtocol.SpatialMode] = []
    /// Кривая продвинутого эквалайзера — рабочая копия. Пока ползунок ещё
    /// не отпущен и запись не ушла, показываем своё, а не то, что на
    /// устройстве: иначе значение прыгало бы назад посреди перетаскивания.
    @Published private(set) var curve: NothingProtocol.EQCurve?

    /// Отложенная запись кривой. Донор ждёт 300 мс после последнего движения
    /// ползунка — иначе каждое движение уходит на провод отдельным кадром.
    private var curveWrite: DispatchWorkItem?

    /// Взаимоисключение баса и продвинутого эквалайзера с пространственным
    /// звуком — свойство модели из каталога, а не поведение по умолчанию.
    /// Выставляется владельцем, когда известны модель и прошивка.
    var mutuallyExclusive = false

    /// Пространственный звук включён — в этом виде его спрашивает секция баса.
    /// Ждущая запись считается включённой сразу: иначе на время подтверждения
    /// бас остался бы доступен, и человек успел бы нажать заведомо отказное.
    var spatialActive: Bool { (pendingSpatial ?? spatial ?? .off) != .off }

    /// Гейт донора, симметричный: он блокирует не только бас при включённом
    /// пространственном звуке, но и пространственный звук при включённом басе
    /// или расширенном эквалайзере. Одну половину экран уже соблюдал.
    var spatialBlocked: Bool {
        mutuallyExclusive && ((bass?.enabled ?? false) || advancedOn)
    }

    private unowned let link: DeviceLink

    init(link: DeviceLink) { self.link = link }

    func setSpatial(_ mode: NothingProtocol.SpatialMode) {
        pendingSpatial = mode
        link.send(NothingProtocol.encodeSetSpatial(mode, operationID: link.nextOperationID()))
    }

    func setPreset(_ preset: NothingProtocol.EqualiserPreset) {
        pendingPreset = preset
        // Донор перед каждой записью пресета выключает продвинутый
        // эквалайзер, не глядя на его состояние. Повторяем: выбор пресета —
        // это и есть выход из продвинутого режима, других выходов у донора нет.
        link.send(NothingProtocol.encodeSetAdvancedEQEnabled(false, operationID: link.nextOperationID()))
        link.send(NothingProtocol.encodeSetEqualiser(preset, operationID: link.nextOperationID()))
    }

    /// Спросить кривую. Профиль `255` — «текущий», как спрашивает донор;
    /// профиль `0` возвращает то же самое, это проверено проводом.
    func requestCurve() {
        link.send(NothingProtocol.encode(.init(command: 0xC04D,
                                               operationID: link.nextOperationID(),
                                               payload: [0xFF])))
    }

    func setAdvanced(_ on: Bool) {
        link.send(NothingProtocol.encodeSetAdvancedEQEnabled(on, operationID: link.nextOperationID()))
    }

    /// Заменить одну полосу. Меняем рабочую копию сразу, а на провод шлём
    /// с задержкой: ползунок даёт десятки значений в секунду, устройству
    /// нужно только последнее.
    func setBand(_ index: Int, _ band: NothingProtocol.EQBand) {
        guard let curve, index < curve.bands.count else { return }
        var bands = curve.bands
        bands[index] = band
        // Общее усиление пересчитывается по правилу донора: `-max(0, усиления)`,
        // запас против клиппинга. Инициализатор кривой делает это сам.
        self.curve = .init(profile: curve.profile, bands: bands)

        curveWrite?.cancel()
        let job = DispatchWorkItem { [weak self] in
            guard let self, let curve = self.curve else { return }
            self.curveWrite = nil
            self.link.send(NothingProtocol.encodeSetAdvancedEQ(curve,
                                                               operationID: self.link.nextOperationID()))
        }
        curveWrite = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: job)
    }

    func setBass(enabled: Bool, level: Int) {
        pendingBass = (enabled, level)
        link.send(NothingProtocol.encodeSetBassEnhance(enabled: enabled, level: level,
                                                       operationID: link.nextOperationID()))
    }

    func apply(_ frame: NothingProtocol.Frame) {
        switch frame.command {
        // Подтверждения записи значений не несут — применённое видно
        // только чтением.
        case 0x7010: link.request(.equaliser)
        case 0x704F: link.request(.advancedEQEnabled)
        case 0x7051: link.request(.bassEnhance)
        // Запись кривой САМА включает продвинутый эквалайзер — из кода донора
        // это не выводится, поймано сравнением соседнего поля до и после
        // (`Protocol/SPEC-b170.md`). Поэтому перечитываем и признак тоже.
        case 0x7050: link.request(.advancedEQEnabled)
        case 0x404D:
            // Пока отложенная запись ещё не ушла, устройство отвечает старым
            // значением — принимать его значило бы отматывать ползунок назад.
            guard curveWrite == nil else { return }
            curve = NothingProtocol.parseEQCurve(frame)
        case 0x401F:
            preset = NothingProtocol.parseEqualiser(frame)
            pendingPreset = nil
        case 0x404C:
            advancedOn = NothingProtocol.parseSingleValue(frame) == 1
        case 0x404E:
            guard let value = NothingProtocol.parseBassEnhance(frame) else { return }
            // Уровень с провода бывает нулевым, если бас не настраивали ни
            // разу; интерфейс, как у донора, начинает шкалу с единицы.
            bass = (value.enabled, max(1, min(5, value.level)))
            pendingBass = nil
        // Подтверждение записи пространственного звука. Перечитываем и бас:
        // у моделей с взаимоисключением он гаснет не по нашей команде, и
        // соседнее поле обязано быть снято, а не додумано.
        case 0x7052:
            link.request(.spatialAudio)
            link.request(.bassEnhance)
        case 0x404F:
            spatial = NothingProtocol.parseSpatial(frame)
            pendingSpatial = nil
        default: break
        }
    }
}

/// Поведение устройства: пауза при снятии и режим низкой задержки. Оба —
/// тумблеры, оба читаются и пишутся, и оба ничего не знают о звуке, поэтому
/// живут отдельно от `SoundStore`, а не внутри него.
///
/// Кодек тут же, но особый: его запись **перезагружает наушники**. Ответа на
/// перечитывание после неё ждать бесполезно — канал рвётся вместе с
/// устройством. Состояние возвращается само, когда мост поднимет канал и
/// `DeviceLink` переспросит всё заново.
final class DeviceSettingsStore: ObservableObject {
    /// nil — устройство ещё не ответило или команда ему недоступна; секция
    /// тогда не показывается вовсе, как и у звука.
    @Published private(set) var inEar: Bool?
    @Published private(set) var pendingInEar: Bool?
    @Published private(set) var latency: Bool?
    @Published private(set) var pendingLatency: Bool?
    @Published private(set) var codec: NothingProtocol.Codec?
    @Published private(set) var pendingCodec: NothingProtocol.Codec?
    /// Кодеки, доступные модели; наполняется владельцем по каталогу.
    /// Один кодек — выбирать не из чего, секции нет.
    @Published var codecs: [NothingProtocol.Codec] = []
    /// Подключение к двум устройствам: выключатель и список пар.
    @Published private(set) var dualEnabled: Bool?
    @Published private(set) var pendingDual: Bool?
    @Published private(set) var dualDevices: [NothingProtocol.DualDevice] = []
    /// Перезагружаются ли наушники при смене режима. **Отдельный флаг**, а не
    /// следствие поддержки режима: у B170 его нет, и провод это подтвердил —
    /// канал при переключении не рвался. Обещание перезагрузки без флага было
    /// бы враньём, скопированным у донора вместе с его гейтом.
    @Published var dualReboots = false
    /// Список приходит страницами, и запросы надо чем-то ограничить: у донора
    /// потолок двадцать страниц, у нас тот же.
    private var dualPages = 0

    @Published private(set) var personalSound: Bool?
    @Published private(set) var pendingPersonalSound: Bool?
    /// Какими командами читается и пишется персональный звук у этой модели;
    /// nil — не умеет вовсе. Наполняется владельцем по каталогу.
    var personalSoundCommands: (read: UInt16, write: UInt16)?
    /// Куда можно звонить при поиске; пустой список — модель не умеет.
    @Published var ringTargets: [NothingProtocol.RingTarget] = []
    /// Что звенит прямо сейчас. Устройство об окончании не сообщает, поэтому
    /// это наше представление о происходящем, а не снятое состояние.
    @Published private(set) var ringing: NothingProtocol.RingTarget?

    private unowned let link: DeviceLink

    init(link: DeviceLink) { self.link = link }

    func setInEar(_ on: Bool) {
        pendingInEar = on
        link.send(NothingProtocol.encodeSetInEarDetection(on, operationID: link.nextOperationID()))
    }

    func setLatency(_ on: Bool) {
        pendingLatency = on
        link.send(NothingProtocol.encodeSetLatency(on, operationID: link.nextOperationID()))
    }

    /// Позвонить или замолчать. Звонит ровно одна часть за раз: две
    /// одновременно звенящие затычки различить на слух невозможно, а
    /// «найти левую» — весь смысл затеи.
    func ring(_ target: NothingProtocol.RingTarget, _ on: Bool) {
        if on, let ringing, ringing != target { stopRinging(ringing) }
        ringing = on ? target : nil
        link.send(NothingProtocol.encodeRingDevice(target, on: on,
                                                   operationID: link.nextOperationID()))
    }

    private func stopRinging(_ target: NothingProtocol.RingTarget) {
        link.send(NothingProtocol.encodeRingDevice(target, on: false,
                                                   operationID: link.nextOperationID()))
    }

    /// Связь пропала — звонок не остановить и не подтвердить. Честнее забыть
    /// о нём, чем оставить кнопку в состоянии «звенит» навсегда.
    func forgetRinging() { ringing = nil }

    /// Выключатель режима. ⚠ Перезагружает наушники, как и смена кодека:
    /// подтверждение приходит до перезагрузки, перечитывать по нему нечего.
    func setDualEnabled(_ on: Bool) {
        pendingDual = on
        link.send(NothingProtocol.encodeSetDualEnabled(on, operationID: link.nextOperationID()))
    }

    func setDualConnect(_ device: NothingProtocol.DualDevice, _ connect: Bool) {
        link.send(NothingProtocol.encodeSetDualConnect(address: device.address, connect: connect,
                                                       operationID: link.nextOperationID()))
    }

    /// Спросить список с начала.
    func requestDualList() {
        dualDevices = []
        dualPages = 0
        requestNextDualPage()
    }

    private func requestNextDualPage() {
        dualPages += 1
        link.send(NothingProtocol.encodeRequestDualList(known: dualDevices.count,
                                                        operationID: link.nextOperationID()))
    }

    func setPersonalSound(_ on: Bool) {
        guard let write = personalSoundCommands?.write else { return }
        pendingPersonalSound = on
        link.send(NothingProtocol.encodeSetPersonalSound(on, command: write,
                                                         operationID: link.nextOperationID()))
    }

    func setCodec(_ codec: NothingProtocol.Codec) {
        pendingCodec = codec
        link.send(NothingProtocol.encodeSetCodec(codec, operationID: link.nextOperationID()))
    }

    func apply(_ frame: NothingProtocol.Frame) {
        switch frame.command {
        // Подтверждения записи значений не несут — применённое видно чтением.
        case 0x7004: link.request(.inEarDetection)
        case 0x7040: link.request(.latencyMode)
        case 0x400E:
            // Ответ несёт весь блок настроек, а не одну запись: детекция в ухе
            // лежит в нём под своим идентификатором, остальные пока без имени.
            guard let value = NothingProtocol.parseInEarDetection(frame) else { return }
            inEar = value
            pendingInEar = nil
        case 0x4041:
            latency = NothingProtocol.parseLatency(frame)
            pendingLatency = nil
        case 0x4027:
            dualEnabled = NothingProtocol.parseSingleValue(frame) == 1
            pendingDual = nil
        case 0x4028:
            // Страница списка. Новые устройства дописываем, известные обновляем;
            // пока страница приносит новое — просим следующую.
            var added = false
            for device in NothingProtocol.parseDualList(frame) {
                if let i = dualDevices.firstIndex(where: { $0.address == device.address }) {
                    dualDevices[i] = device
                } else {
                    dualDevices.append(device)
                    added = true
                }
            }
            if added && dualPages < 20 { requestNextDualPage() }
        // Подключение к паре списка не меняет — перечитываем его целиком.
        case 0x701B: requestDualList()
        // Незапрошенное событие о паре. Приходит ли оно у B170 — не проверено,
        // как и прочие push; разбор дешёвый, и если придёт, список обновится.
        case 0xE019:
            let p = frame.payload
            guard p.count >= 7 else { return }
            let address = Array(p[1..<7])
            if let i = dualDevices.firstIndex(where: { $0.address == address }) {
                let old = dualDevices[i]
                dualDevices[i] = .init(address: old.address, name: old.name,
                                       isSelf: old.isSelf, isConnected: p[0] == 1)
            } else {
                requestDualList()
            }
        // Ответ и подтверждение персонального звука — у каждого поставщика
        // профиля свои коды, поэтому сравниваем с тем, что выбрал каталог.
        case personalSoundCommands.map({ $0.read & 0x7FFF | 0x4000 }):
            personalSound = NothingProtocol.parseSingleValue(frame) == 1
            pendingPersonalSound = nil
        case personalSoundCommands.map({ $0.write & 0x7FFF | 0x7000 }):
            if let read = personalSoundCommands?.read,
               let command = NothingProtocol.Command(rawValue: read) { link.request(command) }
        // Подтверждение смены кодека приходит ДО перезагрузки, поэтому
        // перечитывать по нему нечего: ответ уже некому будет прислать.
        // Ждём восстановления канала — оно переспросит само.
        case 0x701C: break
        case 0x4029:
            codec = NothingProtocol.parseCodec(frame)
            pendingCodec = nil
        default: break
        }
    }
}

/// Жесты. Хранилище помнит больше, чем показывает: «шумоподавление» приходит
/// с провода кодом состава круга (у B170 колесо стоит в 0x16 — круг без
/// «выключено»), и запись выбора пользователя обязана этот состав сохранить.
/// Затереть его каталожным 0x0A значило бы молча вернуть «выключено» в круг
/// всякий раз, когда пользователь ушёл с шумоподавления и передумал.
final class GestureStore: ObservableObject {
    @Published private(set) var rows: [NothingProtocol.Gesture] = []
    @Published private(set) var pending: NothingProtocol.Gesture?
    /// Раскладка модели из каталога; наполняется владельцем, когда известны
    /// модель и прошивка. Пустая раскладка — секции жестов нет.
    @Published var slots: [NothingCatalog.GestureSlot] = []

    /// Последний виденный код круга каждой строки.
    private var lastCycle = [UInt32: UInt8]()

    private unowned let link: DeviceLink

    init(link: DeviceLink) { self.link = link }

    private func key(_ device: UInt8, _ button: UInt8, _ gesture: UInt8) -> UInt32 {
        UInt32(device) << 16 | UInt32(button) << 8 | UInt32(gesture)
    }

    /// Текущее действие слота — для интерфейса, приведённое: код круга
    /// становится «шумоподавлением». Пока подтверждение записи не пришло,
    /// показывается записываемое, иначе кнопка нажималась бы с задержкой
    /// в полный круг «запись → подтверждение → чтение → ответ».
    func current(_ slot: NothingCatalog.GestureSlot) -> NothingCatalog.GestureAction? {
        if let pending, pending.device == slot.device, pending.button == slot.button,
           pending.gesture == slot.gesture.rawValue {
            return NothingCatalog.GestureAction(wire: pending.action)
        }
        guard let row = rows.first(where: {
            $0.device == slot.device && $0.button == slot.button
                && $0.gesture == slot.gesture.rawValue }) else { return nil }
        return NothingCatalog.GestureAction(wire: row.action)
    }

    func set(_ slot: NothingCatalog.GestureSlot, to action: NothingCatalog.GestureAction) {
        // Выбранное «шумоподавление» уходит на провод последним виденным
        // составом круга этой строки; полный круг — только если состава
        // никто никогда не видел.
        let wire = action == .noiseControl
            ? lastCycle[key(slot.device, slot.button, slot.gesture.rawValue)] ?? action.rawValue
            : action.rawValue
        let gesture = NothingProtocol.Gesture(device: slot.device, button: slot.button,
                                              gesture: slot.gesture.rawValue, action: wire)
        pending = gesture
        link.send(NothingProtocol.encodeSetGesture(gesture, operationID: link.nextOperationID()))
    }

    func apply(_ frame: NothingProtocol.Frame) {
        if frame.command == 0x7003 { link.request(.gestures); return }
        guard frame.command == 0x4018 else { return }
        rows = NothingProtocol.parseGestures(frame)
        pending = nil
        for row in rows where NothingProtocol.noiseCycle(row.action) != nil {
            lastCycle[key(row.device, row.button, row.gesture)] = row.action
        }
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

private func title(_ noise: NothingProtocol.NoiseMode) -> String {
    switch noise {
    case .cancelling:   return "Noise cancellation"
    case .transparency: return "Transparency"
    case .off:          return "Off"
    }
}

private func title(_ strength: NothingProtocol.NoiseStrength) -> String {
    switch strength {
    case .low:      return "Low"
    case .mid:      return "Mid"
    case .high:     return "High"
    case .adaptive: return "Adaptive"
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

/// Подписи пресетов — как на странице донора. Комментарий в шапке его
/// `eq_two.js` обещает другие номера и врёт: подписи сверены с диспетчером
/// `setEQfromRead` и разметкой кнопок, а на слух пресеты не проверялись.
private func title(_ preset: NothingProtocol.EqualiserPreset) -> String {
    switch preset {
    case .balanced: return "Balanced"
    case .voice:    return "Voice"
    case .treble:   return "More Treble"
    case .bass:     return "More Bass"
    case .custom:   return "Custom"
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

/// Строка жестов подписывается органом и жестом: «Roller · Hold». Орган
/// берётся из каталога; где он не назван, его заменяет сторона или циферблат
/// из номера устройства, а у единственной кнопки хватает и одного жеста.
private func title(_ slot: NothingCatalog.GestureSlot) -> String {
    let organ: String?
    switch slot.control {
    case .roller: organ = "Roller"
    case .button: organ = "Button"
    case .slider: organ = "Slider"
    case nil:
        switch slot.device {
        case 2: organ = "Left"
        case 3: organ = "Right"
        case 4: organ = "Dial"
        default: organ = nil
        }
    }
    let gesture: String
    switch slot.gesture {
    case .singlePress:     gesture = "Press"
    case .doublePress:     gesture = "Double press"
    case .triplePress:     gesture = "Triple press"
    case .slide:           gesture = "Slide"
    case .pressHold:       gesture = "Hold"
    case .doublePressHold: gesture = "Double press and hold"
    case .rotate:          gesture = "Rotate"
    case .pinchBoth:       gesture = "Pinch both"
    }
    return organ.map { "\(t($0)) · \(t(gesture))" } ?? t(gesture)
}

/// Выбор языка. Живёт и на стартовом экране тоже: русскоязычному человеку,
/// у которого не открывается канал, английская подсказка бесполезна ровно
/// тогда, когда она нужнее всего.
struct LanguagePicker: View {
    @ObservedObject private var strings = Strings.shared

    var body: some View {
        Picker(t("Language"), selection: $strings.language) {
            ForEach(Language.allCases) { language in
                Text(language.title).tag(language)
            }
        }
    }
}

/// Имена свои, смысл сверен с подписями кнопок донора: 32 — «Channel Hop»,
/// 33 — «Essential Space», 34 — перебор пресетов эквалайзера.
private func title(_ action: NothingCatalog.GestureAction) -> String {
    switch action {
    case .noAction:         return "No action"
    case .playPause:        return "Play / pause"
    case .answerCall:       return "Answer call"
    case .skipBack:         return "Previous track"
    case .skipForward:      return "Next track"
    case .noiseControl:     return "Noise control"
    case .voiceAssistant:   return "Voice assistant"
    case .lowLagMode:       return "Low lag mode"
    case .volumeUp:         return "Volume up"
    case .volumeDown:       return "Volume down"
    case .volumeControl:    return "Volume"
    case .cameraShutter:    return "Camera shutter"
    case .answerCallAndMute: return "Answer and mute"
    case .hangUp:           return "Hang up"
    case .spatialAudio:     return "Spatial audio"
    case .micMute:          return "Mic mute"
    case .news:             return "News reporter"
    case .radio:            return "Channel hop"
    case .essentialSpace:   return "Essential Space"
    case .eqPreset:         return "EQ preset"
    case .ultraBass:        return "Ultra bass"
    case .trebleEnhance:    return "Treble enhance"
    case .recording:        return "Recording"
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
        case .idle:             return t("Not connected")
        case .connecting:       return t("Connecting…")
        case .ready:            return t("Connected")
        case .lost(let reason): return t(reason)
        }
    }
}

/// Портрет устройства: системный значок по форме из таблицы опознания.
/// Рендеров изделий у нас нет и быть не должно — они чужие, — а форма
/// у нас есть, и накладные от затычек значком отличаются.
///
/// Подложка семантическая: она светлеет и темнеет вместе с системой,
/// в отличие от любого подобранного цвета.
struct DevicePortrait: View {
    /// Нет опознания — рисуем накладные: это самое узнаваемое из двух,
    /// и пустое место было бы хуже неточности.
    let form: NothingCatalog.FormFactor?

    private var symbol: String {
        switch form {
        // `earbuds` появился в macOS 12, планка проекта 13 — можно.
        case .earbuds: return "earbuds"
        case .overEar, nil: return "headphones"
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
        }
        .frame(width: 48, height: 48)
    }
}

struct DeviceHeader: View {
    let name: String?
    let status: DeviceLink.Status
    let charge: NothingProtocol.Battery.Reading?
    let form: NothingCatalog.FormFactor?
    let reconnect: () -> Void

    var body: some View {
        GlassPanel {
            HStack(spacing: 14) {
                DevicePortrait(form: form)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? t("Nothing device"))
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
                    Button(t("Reconnect"), action: reconnect).glassy()
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
        Section(t("Battery")) {
            if readings.isEmpty {
                Text(t("No reading yet")).foregroundStyle(.secondary)
            } else {
                ForEach(readings, id: \.component) { reading in
                    LabeledContent(t(title(reading.component))) {
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

/// Шумоподавление двумя контролами, а не одним рядом: вид обработки сверху,
/// сила отдельно и только когда она имеет смысл. Так же устроен и донор —
/// у него сила живёт своим селектором, а состав ступеней задаёт маска
/// `ancLevel`; одна строка из шести кнопок была нашим упрощением.
struct ListeningSection: View {
    let mode: NothingProtocol.ListeningMode?
    let pending: NothingProtocol.ListeningMode?
    let strengths: [NothingProtocol.NoiseStrength]
    let hasTransparency: Bool
    let enabled: Bool
    let selectNoise: (NothingProtocol.NoiseMode) -> Void
    let selectStrength: (NothingProtocol.NoiseStrength) -> Void

    private var shown: NothingProtocol.ListeningMode? { pending ?? mode }

    private var modes: [NothingProtocol.NoiseMode] {
        hasTransparency ? [.cancelling, .transparency, .off] : [.cancelling, .off]
    }

    var body: some View {
        Section(t("Listening mode")) {
            // Выбор необязательный: пока устройство не ответило, не выбрано
            // ничего — честнее, чем показать «Off» до первого чтения.
            Picker(t("Mode"), selection: Binding<NothingProtocol.NoiseMode?>(
                get: { shown?.noise },
                set: { if let value = $0 { selectNoise(value) } })) {
                ForEach(modes, id: \.self) { value in
                    Text(t(title(value))).tag(Optional(value))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!enabled)

            // Сила показывается только у шумоподавления и только если модель
            // даёт выбирать: у части моделей селектора нет вовсе.
            if shown?.noise == .cancelling && !strengths.isEmpty {
                LabeledContent(t("Strength")) {
                    Picker(t("Strength"), selection: Binding<NothingProtocol.NoiseStrength?>(
                        get: { shown?.strength },
                        set: { if let value = $0 { selectStrength(value) } })) {
                        ForEach(strengths, id: \.self) { value in
                            Text(t(title(value))).tag(Optional(value))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }
                .disabled(!enabled)
            }

            if let shown {
                HStack(spacing: 6) {
                    Text(t(caption(shown)))
                    if pending != nil && pending != mode {
                        Text(t("· applying…"))
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct EqualiserSection: View {
    let preset: NothingProtocol.EqualiserPreset?
    let pending: NothingProtocol.EqualiserPreset?
    let advancedOn: Bool
    let enabled: Bool
    let select: (NothingProtocol.EqualiserPreset) -> Void

    var body: some View {
        Section(t("Equaliser")) {
            // При активном продвинутом эквалайзере не выбрано ничего:
            // устройство в этот момент играет по кривой, а не по пресету,
            // и подсвеченный пресет был бы враньём.
            Picker(t("Preset"), selection: Binding<NothingProtocol.EqualiserPreset?>(
                get: { pending ?? (advancedOn ? nil : preset) },
                set: { if let value = $0 { select(value) } })) {
                ForEach(NothingProtocol.EqualiserPreset.allCases, id: \.self) { value in
                    Text(t(title(value))).tag(Optional(value))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!enabled)

            if advancedOn && pending == nil {
                Text(t("Advanced EQ is active on the headphones — picking a preset switches it off."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if pending != nil && pending != preset {
                Text(t("Applying…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Границы ползунков и диапазоны полос — из кода донора, не выдуманы:
/// `ADVANCED_EQ_GAIN_MIN/MAX`, `ADVANCED_EQ_QUALITY_MIN/MAX` и
/// `ADVANCED_EQ_BAND_RANGES`. Центры совпали с тем, что вернуло железо,
/// до числа (`Protocol/SPEC-b170.md`).
enum AdvancedEQLimits {
    static let gain: ClosedRange<Double> = -6...6
    static let quality: ClosedRange<Double> = 0.1...10
    /// Полосы можно двигать по частоте, но каждую — только в своём коридоре.
    static let bands: [ClosedRange<Double>] = [
        20...99, 100...199, 200...399, 400...999,
        1000...2999, 3000...5999, 6000...11999, 12000...20000,
    ]
}

private func hertz(_ value: Float) -> String {
    value >= 1000 ? String(format: "%.1f %@", value / 1000, t("kHz"))
                  : String(format: "%.0f %@", value, t("Hz"))
}

/// Тонкая настройка по частотам. У донора это восемь вертикальных ползунков
/// усиления, а частота и добротность появляются для выбранной полосы —
/// здесь то же самое, но горизонтально: в списке macOS так читается лучше.
struct AdvancedEQSection: View {
    let curve: NothingProtocol.EQCurve
    let active: Bool
    /// Взаимоисключение, третья его нога: у моделей с флагом расширенный
    /// эквалайзер не живёт вместе с пространственным звуком. Гейт нужен
    /// именно здесь, а не только на тумблере: движение ползунка шлёт
    /// `0xF050`, а он включает расширенный эквалайзер сам.
    let blocked: Bool
    let enabled: Bool
    @Binding var selected: Int
    let setActive: (Bool) -> Void
    let setBand: (Int, NothingProtocol.EQBand) -> Void

    private var band: NothingProtocol.EQBand? {
        selected < curve.bands.count ? curve.bands[selected] : nil
    }

    private var off: Bool { !enabled || blocked }

    @ViewBuilder
    private func gain(at index: Int) -> some View {
        if index < curve.bands.count {
            let band = curve.bands[index]
            LabeledContent(hertz(band.frequency)) {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { Double(band.gain) },
                        set: { setBand(index, .init(filterType: band.filterType,
                                                    gain: Float($0),
                                                    frequency: band.frequency,
                                                    quality: band.quality)) }),
                        in: AdvancedEQLimits.gain, step: 0.5)
                        .frame(width: 240)
                    Text(String(format: "%+.1f %@", band.gain, t("dB")))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 66, alignment: .trailing)
                }
            }
            .disabled(off)
        }
    }

    var body: some View {
        Section(t("Advanced equaliser")) {
            Toggle(t("Advanced equaliser"), isOn: Binding(
                get: { active }, set: setActive))
                .disabled(off)

            ForEach(0..<curve.bands.count, id: \.self) { index in
                gain(at: index)
            }

            if let band {
                Picker(t("Fine tune"), selection: $selected) {
                    ForEach(Array(curve.bands.enumerated()), id: \.offset) { index, each in
                        Text(hertz(each.frequency)).tag(index)
                    }
                }
                .disabled(off)

                Group {
                    LabeledContent(t("Frequency")) {
                        HStack(spacing: 10) {
                            Slider(value: Binding(
                                get: { Double(band.frequency) },
                                set: { setBand(selected, .init(filterType: band.filterType,
                                                               gain: band.gain,
                                                               frequency: Float($0),
                                                               quality: band.quality)) }),
                                in: AdvancedEQLimits.bands[min(selected, AdvancedEQLimits.bands.count - 1)],
                                step: 1)
                                .frame(width: 240)
                            Text(hertz(band.frequency))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 66, alignment: .trailing)
                        }
                    }
                    LabeledContent(t("Q factor")) {
                        HStack(spacing: 10) {
                            Slider(value: Binding(
                                get: { Double(band.quality) },
                                set: { setBand(selected, .init(filterType: band.filterType,
                                                               gain: band.gain,
                                                               frequency: band.frequency,
                                                               quality: Float($0))) }),
                                in: AdvancedEQLimits.quality, step: 0.1)
                                .frame(width: 240)
                            Text(String(format: "%.1f", band.quality))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 66, alignment: .trailing)
                        }
                    }
                }
                .disabled(off)
            }

            if blocked {
                Text(t("Not available while spatial audio is on."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !active {
                // Запись значений включает продвинутый эквалайзер сама —
                // проверено железом. Честнее сказать это заранее, чем дать
                // тумблеру перещёлкнуться будто бы сам собой.
                Text(t("Moving a slider switches the advanced equaliser on and replaces the preset."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BassSection: View {
    let bass: (enabled: Bool, level: Int)
    let pending: (enabled: Bool, level: Int)?
    let blocked: Bool
    let enabled: Bool
    let set: (Bool, Int) -> Void

    private var shownEnabled: Bool { pending?.enabled ?? bass.enabled }
    private var shownLevel: Int { pending?.level ?? bass.level }

    var body: some View {
        Section(t("Bass")) {
            Toggle(t("Bass enhance"), isOn: Binding(
                get: { shownEnabled },
                set: { set($0, shownLevel) }))
                .disabled(!enabled || blocked)

            LabeledContent(t("Level")) {
                Picker(t("Level"), selection: Binding(
                    get: { shownLevel },
                    set: { set(shownEnabled, $0) })) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            .disabled(!enabled || blocked || !shownEnabled)

            if blocked {
                // Гейт донора, повторённый по флагу модели: у B170 бас и
                // пространственный звук не живут одновременно.
                Text(t("Not available while spatial audio is on."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Подпись режима пространственного звука. Живёт в экране, а не в кодеке:
/// кодек знает байты, а как это назвать человеку — забота интерфейса.
func title(_ mode: NothingProtocol.SpatialMode) -> String {
    switch mode {
    case .off:         return t("Off")
    case .headTracked: return t("Head tracking")
    case .fixed:       return t("Fixed")
    case .concert:     return t("Concert")
    case .theatre:     return t("Theatre")
    case .game:        return t("Game")
    }
}

/// Пространственный звук. Состав режимов — из каталога по маске модели:
/// у B170 это «выключено», «следит за головой» и «фиксированный», а концерта,
/// театра и игры нет, хотя протокол их выражает.
struct SpatialSection: View {
    let mode: NothingProtocol.SpatialMode
    let modes: [NothingProtocol.SpatialMode]
    let blocked: Bool
    let enabled: Bool
    let select: (NothingProtocol.SpatialMode) -> Void

    var body: some View {
        Section(t("Spatial audio")) {
            Picker(t("Spatial audio"), selection: Binding(get: { mode }, set: select)) {
                ForEach(modes, id: \.self) { Text(title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!enabled || blocked)

            if blocked {
                // Гейт донора, вторая его половина: не только бас недоступен
                // при пространственном звуке, но и наоборот.
                Text(t("Not available while bass enhance or the advanced equaliser is on."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Поведение устройства: пауза при снятии и режим низкой задержки. Каждый
/// тумблер появляется только после ответа устройства — нет ответа, нет строки.
struct DeviceSection: View {
    let inEar: Bool?
    let pendingInEar: Bool?
    let latency: Bool?
    let pendingLatency: Bool?
    let codec: NothingProtocol.Codec?
    let pendingCodec: NothingProtocol.Codec?
    let codecs: [NothingProtocol.Codec]
    let personalSound: Bool?
    let pendingPersonalSound: Bool?
    let setPersonalSound: (Bool) -> Void
    let enabled: Bool
    let setInEar: (Bool) -> Void
    let setLatency: (Bool) -> Void
    let setCodec: (NothingProtocol.Codec) -> Void

    var body: some View {
        Section(t("Device")) {
            if let inEar {
                Toggle(t("Pause when removed"), isOn: Binding(
                    get: { pendingInEar ?? inEar }, set: setInEar))
                    .disabled(!enabled)
            }
            if let latency {
                Toggle(t("Low latency mode"), isOn: Binding(
                    get: { pendingLatency ?? latency }, set: setLatency))
                    .disabled(!enabled)
            }
            if let personalSound {
                Toggle(t("Personal sound"), isOn: Binding(
                    get: { pendingPersonalSound ?? personalSound }, set: setPersonalSound))
                    .disabled(!enabled)
            }
            if let codec, codecs.count > 1 {
                LabeledContent(t("Codec")) {
                    Picker(t("Codec"), selection: Binding(
                        get: { pendingCodec ?? codec }, set: setCodec)) {
                        ForEach(codecs, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                .disabled(!enabled)
                // Не предупреждение ради вежливости: наушники физически уходят
                // из эфира на несколько секунд, музыка обрывается.
                Text(t("Switching the codec reboots the headphones."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Подпись части устройства, к которой адресован поиск.
func title(_ target: NothingProtocol.RingTarget) -> String {
    switch target {
    case .whole: return t("Headphones")
    case .component(let id):
        switch id {
        case 2:  return t("Left")
        case 3:  return t("Right")
        default: return t("Headphones")
        }
    }
}

/// Поиск устройства. Кнопка на каждую часть, которую модель умеет звать:
/// у полноразмерных одна, у затычек левая и правая.
struct FindSection: View {
    let targets: [NothingProtocol.RingTarget]
    let ringing: NothingProtocol.RingTarget?
    let enabled: Bool
    let ring: (NothingProtocol.RingTarget, Bool) -> Void

    var body: some View {
        Section(t("Find device")) {
            ForEach(targets, id: \.self) { target in
                LabeledContent(title(target)) {
                    Button(ringing == target ? t("Stop") : t("Play sound")) {
                        ring(target, ringing != target)
                    }
                    .glassy()
                }
                .disabled(!enabled)
            }
        }
    }
}

/// Подключение к двум устройствам сразу. Выключатель режима плюс список пар:
/// имена показываем, адреса — никогда, они нужны только чтобы адресовать
/// команду.
struct DualSection: View {
    let enabledMode: Bool
    let pending: Bool?
    let devices: [NothingProtocol.DualDevice]
    let reboots: Bool
    let enabled: Bool
    let setEnabled: (Bool) -> Void
    let connect: (NothingProtocol.DualDevice, Bool) -> Void

    var body: some View {
        Section(t("Dual connection")) {
            Toggle(t("Dual connection"), isOn: Binding(
                get: { pending ?? enabledMode }, set: setEnabled))
                .disabled(!enabled)

            ForEach(devices, id: \.address) { device in
                LabeledContent(device.name.isEmpty ? t("Unnamed device") : device.name) {
                    if device.isSelf {
                        // Себя не отключают: отключишь — оборвёшь ту самую
                        // связь, которой отключал.
                        Text(t("This Mac")).foregroundStyle(.secondary)
                    } else {
                        Button(device.isConnected ? t("Disconnect") : t("Connect")) {
                            connect(device, !device.isConnected)
                        }
                        .glassy()
                    }
                }
                .disabled(!enabled)
            }

            if reboots {
                Text(t("Switching the mode reboots the headphones."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Строка секции жестов, подготовленная к показу: слот каталога плюс текущее
/// действие с провода. Слот без строки с провода в раскладку не попадает —
/// предлагать запись туда, чьё существование устройство не подтвердило, рано.
struct GestureRow: Identifiable {
    let slot: NothingCatalog.GestureSlot
    let selection: NothingCatalog.GestureAction
    let title: String
    var id: String { "\(slot.device)-\(slot.button)-\(slot.gesture.rawValue)" }
}

struct GesturesSection: View {
    let rows: [GestureRow]
    let enabled: Bool
    let select: (NothingCatalog.GestureSlot, NothingCatalog.GestureAction) -> Void

    var body: some View {
        Section(t("Controls")) {
            ForEach(rows) { row in
                Picker(row.title, selection: Binding(
                    get: { row.selection },
                    set: { select(row.slot, $0) })) {
                    ForEach(row.slot.actions, id: \.self) { action in
                        Text(t(title(action))).tag(action)
                    }
                }
                .disabled(!enabled)
            }
        }
    }
}

/// Стартовый экран: пока устройство не отвечало ни разу. Заменяет собой
/// стартовую страницу чужого сайта — со своим значком и своим текстом.
/// Их логотип и название сюда не переносятся: чужого в бандле нет и не будет,
/// а значок приложение рисует само (`Tools/make-icon.swift`).
struct ConnectView: View {
    let status: DeviceLink.Status
    let connect: () -> Void

    private var busy: Bool { status == .connecting }

    private var headline: String {
        switch status {
        case .idle:       return t("Connect your headphones")
        case .connecting: return t("Looking for your headphones…")
        case .ready:      return t("Connected")
        case .lost:       return t("Couldn’t connect")
        }
    }

    private var detail: String {
        switch status {
        case .idle:
            return t("The app talks to Nothing and CMF headphones over Bluetooth.")
        case .connecting:
            return t("Opening the identification and control channels.")
        case .ready:
            return ""
        // Причина приходит от моста и от системы: свои строки переводим,
        // системные оставляем как есть — придумывать им перевод значило бы
        // переписывать то, что сказала macOS.
        case .lost(let reason):
            return t(reason)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.bottom, 18)

            Text(headline)
                .font(.title2.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 4)

            Button(busy ? t("Connecting…") : t("Connect"), action: connect)
                .controlSize(.large)
                .disabled(busy)
                .padding(.top, 20)

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("If nothing happens, check that:"))
                        .font(.callout.weight(.medium))
                    // Три причины, по которым канал не открывается, — те же,
                    // что ловились в логе моста: устройство выключено, оно не
                    // сопряжено, либо канал занят другой программой.
                    ForEach(["the headphones are switched on and out of the case",
                             "they are paired in System Settings › Bluetooth",
                             "no other app is holding the connection"], id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(t(line))
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 420)
            .padding(.top, 26)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
        .padding(.top, 34)
        .padding(.bottom, 24)
    }
}

struct DeviceScreen: View {
    @ObservedObject var link: DeviceLink
    @ObservedObject var battery: BatteryStore
    @ObservedObject var listening: ListeningStore
    @ObservedObject var sound: SoundStore
    @ObservedObject var deviceSettings: DeviceSettingsStore
    @ObservedObject var gestures: GestureStore
    let reconnect: () -> Void

    /// Какая полоса эквалайзера сейчас донастраивается. Живёт в экране, а не
    /// в хранилище: устройство про этот выбор ничего не знает.
    @State private var band = 0

    /// Язык наблюдается корнем, а не каждой подписью. Одного наблюдения мало:
    /// SwiftUI перерисовывает `body` корня, но дочернее представление, у
    /// которого не изменилось ни одно поле, пропускает — а язык ни в одно поле
    /// не входит, он читается функцией `t(...)` внутри. Поэтому корню ставится
    /// `.id(язык)`: смена языка меняет тождество поддерева, и оно строится
    /// заново целиком. Без этого на экране остаётся смесь двух языков —
    /// заголовки вкладок переводятся, а всё внутри нет.
    ///
    /// Цена: при переключении языка сбрасывается выбранная вкладка и выбранная
    /// полоса эквалайзера. Язык переключают редко, и это дешевле, чем тащить
    /// его параметром в каждое представление.
    @ObservedObject private var strings = Strings.shared
    @ObservedObject private var appearance = Appearance.shared

    private var gestureRows: [GestureRow] {
        let base: [(NothingCatalog.GestureSlot, NothingCatalog.GestureAction, String)] =
            gestures.slots.compactMap { slot in
                gestures.current(slot).map { (slot, $0, title(slot)) }
            }
        // Слоты без имени органа могут совпасть подписями — у B198 это два
        // «Hold» на разных кнопках. Тогда подпись дополняется номером кнопки:
        // некрасиво, но честно, и по-настоящему различимо.
        var seen = [String: Int]()
        for row in base { seen[row.2, default: 0] += 1 }
        return base.map { slot, selection, name in
            GestureRow(slot: slot, selection: selection,
                       title: seen[name]! > 1 ? "\(name) · \(slot.button)" : name)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            appearanceBar
            // Пока связи не было ни разу — стартовый экран. После первой
            // удачи остаётся экран устройства: обрыв на простое штатен, мост
            // его чинит сам, и подменять весь интерфейс на каждый обрыв было
            // бы враньём про то, что произошло.
            if link.everConnected { device } else { ConnectView(status: link.status, connect: reconnect) }
        }
        .id(strings.resolved)
    }

    /// Настройки самого приложения — вверху и всегда на виду, в том числе
    /// на стартовом экране: человеку, у которого не открывается канал,
    /// подсказка на чужом языке бесполезна ровно тогда, когда она нужнее.
    private var appearanceBar: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Picker("", selection: $appearance.theme) {
                ForEach(Theme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            LanguagePicker()
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
    }

    private var device: some View {
        VStack(spacing: 0) {
            DeviceHeader(name: link.deviceName,
                         status: link.status,
                         charge: battery.readings.first,
                         form: link.identity?.formFactor,
                         reconnect: reconnect)
                .padding(.top, 12)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            // Вкладки, а не одна простыня в две колонки.
            //
            // Раскладка руками сломалась четыре раза подряд: секций стало
            // десять, и подобранная под них высота окна перестала помещаться
            // на встроенный экран (932 точки против наших 1040). Вкладка
            // ограничивает содержимое сама, и следующая добавленная
            // возможность ломает одну вкладку, а не весь экран.
            TabView {
                // Порядок вкладок — решение владельца: звук первым, он и есть
                // то, ради чего в драйвер заходят чаще всего.
                pair(soundTab, advancedTab).tabItem { Text(t("Sound")) }
                pair(deviceTab, connectionsTab).tabItem { Text(t("Headphones")) }
                single(controlsTab).tabItem { Text(t("Controls")) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(minWidth: 1040)
    }

    /// Две колонки внутри вкладки.
    private func pair<L: View, R: View>(_ left: L, _ right: R) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Form { left }.formStyle(.grouped)
            Form { right }.formStyle(.grouped)
        }
    }

    /// Одна колонка во всю ширину — для вкладок, которым вторая не нужна.
    private func single<V: View>(_ content: V) -> some View {
        Form { content }.formStyle(.grouped)
    }

    /// Вкладка «Наушники»: заряд, обработка звука снаружи и поведение устройства.
    @ViewBuilder
    private var deviceTab: some View {
        BatterySection(readings: battery.readings)
        ListeningSection(mode: listening.mode,
                         pending: listening.pending,
                         strengths: listening.strengths,
                         hasTransparency: listening.hasTransparency,
                         enabled: link.status == .ready,
                         selectNoise: listening.set(noise:),
                         selectStrength: listening.set(strength:))
        if deviceSettings.inEar != nil || deviceSettings.latency != nil
            || deviceSettings.codec != nil || deviceSettings.personalSound != nil {
            DeviceSection(inEar: deviceSettings.inEar,
                          pendingInEar: deviceSettings.pendingInEar,
                          latency: deviceSettings.latency,
                          pendingLatency: deviceSettings.pendingLatency,
                          codec: deviceSettings.codec,
                          pendingCodec: deviceSettings.pendingCodec,
                          codecs: deviceSettings.codecs,
                          personalSound: deviceSettings.personalSound,
                          pendingPersonalSound: deviceSettings.pendingPersonalSound,
                          setPersonalSound: deviceSettings.setPersonalSound,
                          enabled: link.status == .ready,
                          setInEar: deviceSettings.setInEar,
                          setLatency: deviceSettings.setLatency,
                          setCodec: deviceSettings.setCodec)
        }
    }

    /// Правая половина той же вкладки: связи с другими устройствами.
    @ViewBuilder
    private var connectionsTab: some View {
        if let dual = deviceSettings.dualEnabled {
            DualSection(enabledMode: dual,
                        pending: deviceSettings.pendingDual,
                        devices: deviceSettings.dualDevices,
                        reboots: deviceSettings.dualReboots,
                        enabled: link.status == .ready,
                        setEnabled: deviceSettings.setDualEnabled,
                        connect: deviceSettings.setDualConnect)
        }
        if !deviceSettings.ringTargets.isEmpty {
            FindSection(targets: deviceSettings.ringTargets,
                        ringing: deviceSettings.ringing,
                        enabled: link.status == .ready,
                        ring: deviceSettings.ring)
        }
    }

    /// Вкладка «Звук», левая половина: то, что выбирают, а не настраивают.
    @ViewBuilder
    private var soundTab: some View {
        if sound.preset != nil || sound.advancedOn {
            EqualiserSection(preset: sound.preset,
                             pending: sound.pendingPreset,
                             advancedOn: sound.advancedOn,
                             enabled: link.status == .ready,
                             select: sound.setPreset)
        }
        if let bass = sound.bass {
            BassSection(bass: bass,
                        pending: sound.pendingBass,
                        blocked: sound.spatialActive && sound.mutuallyExclusive,
                        enabled: link.status == .ready,
                        set: sound.setBass)
        }
        if let spatial = sound.spatial, sound.spatialModes.count > 1 {
            SpatialSection(mode: sound.pendingSpatial ?? spatial,
                           modes: sound.spatialModes,
                           blocked: sound.spatialBlocked,
                           enabled: link.status == .ready,
                           select: sound.setSpatial)
        }
    }

    /// И правая: восемь полос, которые и гнали окно вниз.
    @ViewBuilder
    private var advancedTab: some View {
        if let curve = sound.curve, !curve.bands.isEmpty {
            AdvancedEQSection(curve: curve,
                              active: sound.advancedOn,
                              blocked: sound.spatialActive && sound.mutuallyExclusive,
                              enabled: link.status == .ready,
                              selected: $band,
                              setActive: sound.setAdvanced,
                              setBand: sound.setBand)
        }
    }

    /// Вкладка «Управление»: раскладка жестов.
    @ViewBuilder
    private var controlsTab: some View {
        if gestureRows.isEmpty {
            Text(t("No reading yet")).foregroundStyle(.secondary)
        } else {
            GesturesSection(rows: gestureRows,
                            enabled: link.status == .ready,
                            select: gestures.set)
        }
    }
}

// MARK: - Окно

/// Единственное место, где известно, что реактивность сделана на
/// `ObservableObject`, и единственное, что связывает транспорт с хранилищами.
final class NativeWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let link = DeviceLink()
    private let battery = BatteryStore()
    private let listening: ListeningStore
    private let sound: SoundStore
    private let deviceSettings: DeviceSettingsStore
    private let gestures: GestureStore

    /// Значок в строке меню. Свойством, а не локальной переменной: локальную
    /// освободят по выходе из `init`, и значок молча исчезнет.
    private var statusItem: NSStatusItem?
    /// Заряд в значке приходится подписывать вручную: `NSStatusItem` — AppKit,
    /// и наблюдать хранилище так, как это делают представления, он не умеет.
    /// Единственное место в проекте, где реактивность видна снаружи SwiftUI.
    private var cancellables = Set<AnyCancellable>()
    private var batteryPoll: Timer?

    override init() {
        listening = ListeningStore(link: link)
        sound = SoundStore(link: link)
        deviceSettings = DeviceSettingsStore(link: link)
        gestures = GestureStore(link: link)

        link.onFrame = { [battery, listening, sound, deviceSettings, gestures] frame in
            battery.apply(frame)
            listening.apply(frame)
            sound.apply(frame)
            deviceSettings.apply(frame)
            gestures.apply(frame)
        }
        // Первый залп — только команды, доступные всем моделям без оговорок.
        // Всё остальное ждёт прошивки: полосы возможностей выбираются по ней.
        link.onReady = { [weak link] in
            link?.request(.battery)
            link?.request(.anc)
            link?.request(.gestures)
            link?.request(.firmware)
        }
        // Окно создаём до содержимого — та же грабля, что с WKWebView.
        // Высота — под полный состав секций B170; на экранах пониже Form
        // прокручивается сам.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 880),
                          // Без `.resizable` намеренно: размер окна фиксирован.
                          // Решение владельца — границы не должны двигаться
                          // вовсе, а не «не ужиматься ниже минимума».
                          styleMask: [.titled, .closable, .miniaturizable,
                                      .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Nothing"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.contentView = NSHostingView(
            rootView: DeviceScreen(link: link, battery: battery, listening: listening,
                                   sound: sound, deviceSettings: deviceSettings,
                                   gestures: gestures,
                                   reconnect: { [weak link] in link?.connect() }))

        // Ограничение размера ставится ПОСЛЕ содержимого, а не до: заданное
        // раньше, оно затирается при установке `contentView`, и окно снова
        // ужимается мышью до прокрутки. Проверено ровно этим способом.
        // Восстановление рамки выключено: иначе система при следующем запуске
        // возвращает прежний размер окна — в том числе тот, до которого его
        // однажды ужали. Ловилось так: окно открывалось 1120×666 при
        // заказанных 1120×820.
        window.isRestorable = false

        // Все хранимые свойства заполнены — только теперь можно к базовому
        // классу и к self. Порядок здесь диктует компилятор, а не вкус.
        super.init()
        window.delegate = self
        installStatusItem()

        // Подписка с захватом self — только когда init доинициализировал
        // все поля: Swift не даст захватить self раньше, и правильно сделает.
        link.onFirmware = { [weak self] _ in self?.applyCatalog() }
        link.onLost = { [deviceSettings] in deviceSettings.forgetRinging() }
    }

    /// Второй залп: всё, что имеет смысл только при известной модели и
    /// прошивке, — раскладка жестов из каталога и команды звука, гейченные
    /// по нему же. Нет опознания в кэше — нет залпа: экран не спрашивает
    /// того, про что каталог не может сказать «поддержано».
    private func applyCatalog() {
        guard let model = link.identity?.base, let firmware = link.firmware else { return }
        sound.mutuallyExclusive =
            NothingCatalog.flags(model: model, firmware: firmware)[.mutuallyExclusive] == 1
        gestures.slots = NothingCatalog.gestures(model: model, firmware: firmware)
        listening.strengths = NothingCatalog.noiseStrengths(model: model, firmware: firmware)
        listening.hasTransparency = NothingCatalog.hasTransparency(model: model, firmware: firmware)
        sound.spatialModes = NothingCatalog.spatialModes(model: model, firmware: firmware)
        deviceSettings.codecs = NothingCatalog.codecs(model: model, firmware: firmware)
        deviceSettings.dualReboots =
            NothingCatalog.flags(model: model, firmware: firmware)[.dualConnectionReboot] == 1
        deviceSettings.ringTargets = NothingCatalog.ringTargets(model: model, firmware: firmware)
        deviceSettings.personalSoundCommands =
            NothingCatalog.personalSound(model: model, firmware: firmware)
        // Список пар спрашивается страницами, поэтому отдельно от общего залпа.
        if let op = NothingCatalog.byCode[NothingProtocol.Command.dualList.rawValue],
           NothingCatalog.supports(op, model: model, firmware: firmware) {
            deviceSettings.requestDualList()
        }
        // Персональный звук спрашивается своей командой: какой именно —
        // решает каталог, а не экран.
        if let read = deviceSettings.personalSoundCommands?.read,
           let op = NothingCatalog.byCode[read],
           NothingCatalog.supports(op, model: model, firmware: firmware),
           let command = NothingProtocol.Command(rawValue: read) {
            link.request(command)
        }
        for command: NothingProtocol.Command in [.equaliser, .advancedEQEnabled,
                                                 .bassEnhance, .spatialAudio,
                                                 .inEarDetection, .latencyMode,
                                                 .highQualityAudio, .dualConnectEnabled] {
            guard let op = NothingCatalog.byCode[command.rawValue],
                  NothingCatalog.supports(op, model: model, firmware: firmware) else { continue }
            link.request(command)
        }
        // Кривая спрашивается отдельно: у неё есть аргумент — номер профиля.
        if let op = NothingCatalog.byCode[NothingProtocol.Command.advancedEQValue.rawValue],
           NothingCatalog.supports(op, model: model, firmware: firmware) {
            sound.requestCurve()
        }
    }

    // MARK: - Строка меню

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "headphones",
                                     accessibilityDescription: t("Nothing device"))
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        // Без этого AppKit шлёт действие только на левую кнопку, и правого
        // клика мы не увидим вовсе.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // Заряд у значка — последний прочитанный.
        battery.$readings
            .receive(on: RunLoop.main)
            .sink { [weak self] readings in
                self?.statusItem?.button?.title =
                    readings.first.map { " \($0.percent)%" } ?? ""
            }
            .store(in: &cancellables)

        startBatteryPoll()
    }

    /// Опрос заряда. Push-событий у наушников нет — проверено на B170
    /// 02.09.2026, — поэтому без опроса число в значке застывает на том,
    /// что пришло при подключении, и живёт так до переподключения.
    ///
    /// Пять минут: заряд меняется на процент за десятки минут, а вопрос
    /// стоит восьми байт. Побочное следствие названо вслух — канал больше
    /// не простаивает пять минут подряд, так что обрыв по простою и молчаливое
    /// восстановление теперь случаются заметно реже. Путь этот не убран
    /// и продолжает работать: разрывает канал не только простой.
    private func startBatteryPoll() {
        batteryPoll?.invalidate()
        batteryPoll = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self, self.link.status == .ready else { return }
            self.link.request(.battery)
        }
    }

    @objc private func statusClicked() {
        // Оба клика показывают меню, и это не упрощение, а единственное, что
        // работает везде. Popover из строки меню не показывается над чужим
        // полноэкранным окном: он живёт в пространстве приложения, а система
        // туда не переключается. Системное меню рисуется поверх всего и не
        // требует, чтобы приложение было активным, — на нём и остановились.
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { showControls() }
    }

    /// Показать меню одним кликом. Назначенное меню перехватывает и левый
    /// клик, поэтому оно живёт ровно один клик: назначили, показали, сняли.
    private func present(_ menu: NSMenu) {
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    /// Левый клик: состояние и то, что меняют чаще всего.
    private func showControls() {
        let menu = NSMenu()

        let name = link.deviceName ?? t("Nothing device")
        let charge = battery.readings.first.map { " · \($0.percent)%" } ?? ""
        let header = NSMenuItem(title: name + charge, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let shown = listening.pending ?? listening.mode
        let modes: [NothingProtocol.NoiseMode] =
            listening.hasTransparency ? [.cancelling, .transparency, .off] : [.cancelling, .off]

        if link.status == .ready {
            menu.addItem(.separator())
            for mode in modes {
                let item = NSMenuItem(title: t(title(mode)), action: #selector(pickNoise(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = mode
                item.state = shown?.noise == mode ? .on : .off
                menu.addItem(item)
            }

            // Уровень — подменю, и только там, где он вообще есть: у части
            // моделей ступеней нет, и пустое подменю солгало бы про модель.
            //
            // Показывается ВСЕГДА, а не только при включённом шумоподавлении.
            // Иначе выбор уровня стоит двух открытий меню: первое включает
            // шумоподавление и закрывается, и только во втором появляется
            // подменю. Выбор уровня сам включает шумоподавление, так что
            // одного клика достаточно и по смыслу.
            if !listening.strengths.isEmpty {
                let levels = NSMenu()
                for strength in listening.strengths {
                    let item = NSMenuItem(title: t(title(strength)),
                                          action: #selector(pickStrength(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = strength
                    item.state = shown?.strength == strength ? .on : .off
                    levels.addItem(item)
                }
                let holder = NSMenuItem(title: t("Level"), action: nil, keyEquivalent: "")
                holder.submenu = levels
                menu.addItem(holder)
            }
        } else {
            let waiting = NSMenuItem(title: t("Looking for headphones…"), action: nil,
                                     keyEquivalent: "")
            waiting.isEnabled = false
            menu.addItem(.separator())
            menu.addItem(waiting)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: t("Open window"), action: #selector(openWindow), keyEquivalent: "")
            .target = self
        present(menu)
    }

    @objc private func pickNoise(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? NothingProtocol.NoiseMode else { return }
        listening.set(noise: mode)
    }

    @objc private func pickStrength(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NothingProtocol.NoiseStrength else { return }
        listening.set(strength: value)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: t("Open window"), action: #selector(openWindow), keyEquivalent: "")
            .target = self
        if let target = deviceSettings.ringTargets.first {
            menu.addItem(.separator())
            let ringing = deviceSettings.ringing != nil
            menu.addItem(withTitle: ringing ? t("Stop") : t("Find headphones"),
                         action: #selector(toggleRing), keyEquivalent: "")
                .target = self
            _ = target
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: t("Quit"), action: #selector(quit), keyEquivalent: "q")
            .target = self
        present(menu)
    }

    @objc private func openWindow() { show() }

    @objc private func toggleRing() {
        guard let target = deviceSettings.ringTargets.first else { return }
        deviceSettings.ring(target, deviceSettings.ringing == nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    /// Крестик прячет окно, а не закрывает его. Драйвер живёт дольше своей
    /// витрины: наушники подключены и тогда, когда смотреть на них не нужно.
    /// Возвращать окно нечем, кроме значка в строке меню и Dock, — поэтому
    /// оба обязаны существовать к этому моменту.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window.orderOut(nil)
        return false
    }

    func show() {
        // Размер задаём при каждом показе: система может ужать окно, если в
        // прошлый раз оно не помещалось на другой экран.
        window.setContentSize(NSSize(width: 1120, height: 880))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Второй и последующие показы канал не трогают: он уже открыт, и
        // переподключение ради показа окна оборвало бы живую связь.
        if link.status == .idle { link.connect() }
    }

    /// Выход любым способом отпускает канал. Не косметика: устройство отдаёт
    /// его одной программе за раз, и не отпустив, мы оставим наушники
    /// недоступными для всех остальных до перезагрузки Bluetooth.
    func shutdown() {
        batteryPoll?.invalidate()
        // Оставить звенящие наушники после выхода — самое обидное, что можно
        // сделать: остановить их будет уже нечем.
        if let ringing = deviceSettings.ringing { deviceSettings.ring(ringing, false) }
        link.close()
    }
}
