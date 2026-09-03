import Foundation

/// Протокол наушников Nothing поверх Bluetooth SPP.
///
/// Слой ничего не знает о транспорте: на вход и выход — байты. Это позволяет
/// проверять его на записанных кадрах, без железа.
///
/// Роль команды кодируется старшим байтом: запрос `0xC0NN` получает ответ `0x40NN`
/// с тем же идентификатором операции, запись `0xF0NN` — подтверждение `0x70NN`,
/// а `0xE0NN` устройство присылает само.
public enum NothingProtocol {

    // MARK: - Кадр

    public struct Frame: Equatable {
        public let command: UInt16
        public let operationID: UInt8
        public let payload: [UInt8]

        public init(command: UInt16, operationID: UInt8, payload: [UInt8] = []) {
            self.command = command
            self.operationID = operationID
            self.payload = payload
        }

        public enum Role: String { case request, response, write, ack, push, unknown }

        public var role: Role {
            switch command >> 8 & 0xF0 {
            case 0xC0: return .request
            case 0x40: return .response
            case 0xF0: return .write
            case 0x70: return .ack
            case 0xE0: return .push
            default:   return .unknown
            }
        }

        /// Ответ, которого следует ждать на этот запрос: у него тот же младший
        /// байт и снятый старший бит роли.
        public var expectedReply: UInt16? {
            switch role {
            case .request: return command & 0x7FFF        // 0xC0NN → 0x40NN
            case .write:   return command & 0x7FFF        // 0xF0NN → 0x70NN
            default:       return nil
            }
        }
    }

    public static let header: [UInt8] = [0x55, 0x60, 0x01]

    public enum DecodeError: Error, Equatable {
        case tooShort(have: Int, need: Int)
        case badHeader
        case badChecksum(expected: UInt16, actual: UInt16)
    }

    /// CRC16-Modbus: полином 0xA001, начальное значение 0xFFFF.
    public static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    public static func encode(_ frame: Frame) -> [UInt8] {
        var bytes = header
        bytes.append(UInt8(frame.command & 0xFF))
        bytes.append(UInt8(frame.command >> 8))
        bytes.append(UInt8(frame.payload.count))
        bytes.append(0x00)
        bytes.append(frame.operationID)
        bytes += frame.payload
        let crc = crc16(bytes)
        bytes.append(UInt8(crc & 0xFF))
        bytes.append(UInt8(crc >> 8))
        return bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> Frame {
        guard bytes.count >= 10 else { throw DecodeError.tooShort(have: bytes.count, need: 10) }
        guard Array(bytes.prefix(3)) == header else { throw DecodeError.badHeader }
        let length = Int(bytes[5])
        let total = 8 + length + 2
        guard bytes.count >= total else { throw DecodeError.tooShort(have: bytes.count, need: total) }
        let body = Array(bytes.prefix(8 + length))
        let expected = crc16(body)
        let actual = UInt16(bytes[8 + length]) | UInt16(bytes[9 + length]) << 8
        guard expected == actual else { throw DecodeError.badChecksum(expected: expected, actual: actual) }
        return Frame(command: UInt16(bytes[3]) | UInt16(bytes[4]) << 8,
                     operationID: bytes[7],
                     payload: Array(body.dropFirst(8)))
    }

    /// Нарезает поток на целые кадры. RFCOMM склеивает и режет доставки, поэтому
    /// разбирать по одной доставке нельзя. Возвращает разобранное и остаток.
    public static func split(_ buffer: [UInt8]) -> (frames: [Frame], rest: [UInt8]) {
        var rest = buffer, frames = [Frame]()
        while rest.count >= 8 {
            guard rest[0] == header[0], rest[1] == header[1] else { rest.removeFirst(); continue }
            let total = 8 + Int(rest[5]) + 2
            guard rest.count >= total else { break }
            if let frame = try? decode(Array(rest.prefix(total))) { frames.append(frame) }
            rest.removeFirst(total)
        }
        return (frames, rest)
    }

    // MARK: - Команды, доступные B170

    public enum Command: UInt16, CaseIterable {
        case battery              = 0xC007
        case anc                  = 0xC01E
        case equaliser            = 0xC01F
        case gestures             = 0xC018
        case inEarDetection       = 0xC00E
        case latencyMode          = 0xC041
        case firmware             = 0xC042
        case advancedEQEnabled    = 0xC04C
        case bassEnhance          = 0xC04E
        case spatialAudio         = 0xC04F
        case personalSound        = 0xC05A
        case dualConnectEnabled   = 0xC027
        case highQualityAudio     = 0xC029

        case setANC               = 0xF00F
        case setEqualiser         = 0xF010
        case listeningMode        = 0xC050
        case setListeningMode     = 0xF01D
        case customEQ             = 0xC044
        case advancedEQValue      = 0xC04D

        case setBassEnhance       = 0xF051
        case setAdvancedEQEnabled = 0xF04F
        case setUTCTime           = 0xF00A
        case ringDevice           = 0xF002
        case setGestures          = 0xF003
        case setCustomEQ          = 0xF041
        case setAdvancedEQValue   = 0xF050
        case setInEarDetection    = 0xF004
        case setPersonalSound     = 0xF05C
        case dualList             = 0xC028
        case setDualEnabled       = 0xF01A
        case setDualConnect       = 0xF01B
        case setPersonalSoundMimi = 0xF015
        case setHighQualityAudio  = 0xF01C
        case setLatency           = 0xF040
        case setSpatialAudio      = 0xF052
    }

    // MARK: - Разбор ответов

    public struct Battery: Equatable {
        public enum Component: UInt8 { case left = 2, right = 3, `case` = 4, stereo = 6 }
        public struct Reading: Equatable {
            public let component: Component
            public let percent: Int
            public let charging: Bool
        }
        public let readings: [Reading]
    }

    /// Ответ `0x4007`: [количество устройств] затем пары [идентификатор, уровень].
    /// Старший бит уровня означает зарядку, остальные семь — проценты.
    public static func parseBattery(_ frame: Frame) -> Battery? {
        guard !frame.payload.isEmpty else { return nil }
        let count = Int(frame.payload[0])
        var readings = [Battery.Reading]()
        for i in 0..<count {
            let base = 1 + i * 2
            guard base + 1 < frame.payload.count,
                  let component = Battery.Component(rawValue: frame.payload[base]) else { continue }
            let raw = frame.payload[base + 1]
            readings.append(.init(component: component,
                                  percent: Int(raw & 0x7F),
                                  charging: raw & 0x80 != 0))
        }
        return Battery(readings: readings)
    }

    /// Ответ `0x4042`: версия прошивки как ASCII.
    public static func parseFirmware(_ frame: Frame) -> String? {
        String(bytes: frame.payload, encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    /// Режим прослушивания. Значение на проводе одно и кодирует и режим, и силу
    /// шумоподавления сразу — отдельного поля силы в протоколе нет.
    ///
    /// Таблица проверена на живом устройстве (Nothing Headphone (1), прошивка
    /// 1.0.1.81): каждое значение выставлялось по одному и оценивалось на слух.
    /// 0x01 заметно глушит фон, 0x05 оставляет только пассивную изоляцию,
    /// 0x07 пропускает внешние звуки. Часть публичных разборов протокола Nothing
    /// меняет 0x05 и 0x07 местами — для этой модели это неверно.
    public enum ListeningMode: UInt8, Equatable, CaseIterable {
        case ancHigh     = 0x01
        case ancMid      = 0x02
        case ancLow      = 0x03
        case ancAdaptive = 0x04
        case off         = 0x05
        case transparency = 0x07

        /// Вид обработки без силы. На проводе они слиты в одно значение,
        /// а на экране это два разных контрола — так же, как у донора,
        /// где сила живёт отдельным селектором и гейтится маской `ancLevel`.
        public var noise: NoiseMode {
            switch self {
            case .transparency: return .transparency
            case .off:          return .off
            default:            return .cancelling
            }
        }

        /// Сила есть только у шумоподавления: у прозрачности и выключенного
        /// её не бывает, и `nil` здесь — факт протокола, а не «не нашли».
        public var strength: NoiseStrength? { NoiseStrength(rawValue: rawValue) }

        /// Собрать обратно. Сила нужна только шумоподавлению, остальным она
        /// безразлична — поэтому у неё есть умолчание.
        public init(noise: NoiseMode, strength: NoiseStrength = .high) {
            switch noise {
            case .transparency: self = .transparency
            case .off:          self = .off
            case .cancelling:   self = ListeningMode(rawValue: strength.rawValue) ?? .ancHigh
            }
        }
    }

    /// Вид обработки внешнего звука.
    public enum NoiseMode: Equatable, CaseIterable {
        case cancelling, transparency, off
    }

    /// Сила шумоподавления. Номера те же, что у режима: сила и есть режим,
    /// отдельного поля силы в протоколе нет.
    public enum NoiseStrength: UInt8, Equatable, CaseIterable {
        case high = 0x01
        case mid  = 0x02
        case low  = 0x03
        case adaptive = 0x04
    }

    /// Ответ `0x401E` и push `0xE003`: режим лежит в `payload[1]`, не в `payload[0]`.
    public static func parseListening(_ frame: Frame) -> ListeningMode? {
        guard frame.payload.count >= 2 else { return nil }
        return ListeningMode(rawValue: frame.payload[1])
    }

    /// Запись `0xF00F`: `[счётчик записей, режим, 0x00]`.
    public static func encodeSetANC(_ mode: ListeningMode, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setANC.rawValue,
                     operationID: operationID,
                     payload: [0x01, mode.rawValue, 0x00]))
    }

    /// Ответ `0x400E` — не одиночный признак, а блок настроек:
    /// `[количество][идентификатор, значение] × N`. Драйвер-донор читает
    /// фиксированное смещение `payload[2]`, то есть значение первой пары,
    /// полагаясь на порядок; разбираем по идентификаторам.
    public static func parseSettings(_ frame: Frame) -> [UInt8: UInt8] {
        guard let count = frame.payload.first else { return [:] }
        var result = [UInt8: UInt8]()
        for i in 0..<Int(count) {
            let base = 1 + i * 2
            guard base + 1 < frame.payload.count else { break }
            result[frame.payload[base]] = frame.payload[base + 1]
        }
        return result
    }

    /// Идентификаторы внутри блока настроек `0x400E`. Названы те, что удалось
    /// сопоставить с интерфейсом; остальные читаются, но пока без имени.
    public enum Setting: UInt8 { case inEarDetection = 0x01 }

    public static func parseInEarDetection(_ frame: Frame) -> Bool? {
        parseSettings(frame)[Setting.inEarDetection.rawValue].map { $0 != 0 }
    }

    /// Запись детекции в ухе `0xF004`: `[0x01, 0x01, признак]`. Первая пара —
    /// это «одна запись, идентификатор 1», то есть та же форма блока настроек,
    /// что и в ответе `0x400E`, только на одну запись.
    public static func encodeSetInEarDetection(_ on: Bool, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setInEarDetection.rawValue,
                     operationID: operationID,
                     payload: [0x01, Setting.inEarDetection.rawValue, on ? 1 : 0]))
    }

    /// Пресет эквалайзера, ответ `0x401F`.
    ///
    /// Значения взяты из диспетчера `setEQfromRead` и подтверждены подписями
    /// кнопок в разметке страницы. Комментарий в шапке того же файла у донора
    /// обещает другое (`1 = More Bass`, `3 = More Voice`, `4 = Custom`) и
    /// разошёлся с собственным кодом — на него не полагаться.
    ///
    /// Шестёрки в списке нет намеренно: «Advanced» на странице выглядит шестым
    /// пресетом, но пресетом не является — кнопка шлёт не `0xF010`, а
    /// включение продвинутого эквалайзера `0xF04F`.
    public enum EqualiserPreset: UInt8, CaseIterable {
        case balanced = 0
        case voice    = 1
        case treble   = 2
        case bass     = 3
        case custom   = 5
    }

    public static func parseEqualiser(_ frame: Frame) -> EqualiserPreset? {
        frame.payload.first.flatMap(EqualiserPreset.init(rawValue:))
    }

    /// Запись `0xF010`: `[пресет, 0x00]`. Второй байт у донора всегда ноль
    /// и никогда не заполняется — но короче кадр он не делает.
    public static func encodeSetEqualiser(_ preset: EqualiserPreset, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setEqualiser.rawValue,
                     operationID: operationID,
                     payload: [preset.rawValue, 0x00]))
    }

    /// Профиль звучания, ответ `0x4050`. Отдельная от пресета команда, но
    /// раскладка та же: значение в первом байте. У донора обе, `0x401F` и
    /// `0x4050`, разбираются одной функцией `readEQ`, и обе берут байт по
    /// одному смещению (`bluetooth_socket.js`, `readEQ`).
    ///
    /// Возвращается сырым числом: имена профилей знает каталог, а кодек
    /// умеет байты и про модели не знает ничего.
    public static func parseSoundProfile(_ frame: Frame) -> UInt8? {
        frame.payload.first
    }

    /// Запись `0xF01D`: `[профиль, 0x00]` — байт в байт та же раскладка, что
    /// у пресета, и у донора это буквально та же функция с другим номером
    /// (`setListeningMode` против `setEQ`).
    public static func encodeSetSoundProfile(_ profile: UInt8, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setListeningMode.rawValue,
                     operationID: operationID,
                     payload: [profile, 0x00]))
    }

    /// Ответы, состоящие из одного значения: `0x404C` продвинутый эквалайзер,
    /// `0x405A` персональный звук, `0x4027` две пары.
    ///
    /// Задержки, кодека и пространственного звука здесь больше нет: у каждого
    /// свой разбор. У пространственного звука значимы **оба** байта — это
    /// снято проводом, — а задержка кодируется единицей и двойкой, а не
    /// признаком, и «одно значение» про неё сказало бы неправду.
    public static func parseSingleValue(_ frame: Frame) -> UInt8? {
        frame.payload.first
    }

    /// Режим низкой задержки, ответ `0x4041` и запись `0xF040`.
    ///
    /// ⚠ Значения **не** булевы и не совпадают с привычным `1/0`: включено —
    /// `1`, выключено — `2`. Ноль на проводе не появляется вовсе. У донора это
    /// видно с двух сторон: `setLatencyModeCheckbox` ставит галку по `1` и
    /// снимает по `2`, а `setLatency(0)` пишет байт `0x02`, а не `0x00`.
    public static func parseLatency(_ frame: Frame) -> Bool? {
        guard let value = frame.payload.first else { return nil }
        return value == 1
    }

    public static func encodeSetLatency(_ on: Bool, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setLatency.rawValue,
                     operationID: operationID,
                     payload: [on ? 1 : 2, 0x00]))
    }

    /// Пространственный звук, ответ `0x404F` и запись `0xF052`: `[режим, голова]`.
    ///
    /// Два байта, и **оба значимы**: «следит за головой» — это не отдельный
    /// режим, а тот же первый режим со вторым байтом `1`. Поэтому разбор
    /// начинается со второго байта, а не с первого, — иначе «следит за головой»
    /// и «фиксированный» слились бы в одно.
    ///
    /// Какие режимы доступны модели — решает маска `spatialAudio` в каталоге;
    /// биты объявлены в таблице донора `SPATIAL_AUDIO_MODES`. «Выключено»
    /// доступно всегда и бита не имеет.
    public enum SpatialMode: UInt8, CaseIterable {
        case off = 0
        case headTracked = 1
        case fixed = 2
        case concert = 3
        case theatre = 4
        case game = 5

        /// Как режим выглядит на проводе.
        public var wire: (mode: UInt8, head: UInt8) {
            switch self {
            case .off:         return (0, 0)
            case .headTracked: return (1, 1)
            case .fixed:       return (1, 0)
            case .concert:     return (2, 0)
            case .theatre:     return (3, 0)
            case .game:        return (4, 0)
            }
        }

        /// Бит маски `spatialAudio`, открывающий режим. У «выключено» его нет:
        /// оно доступно всегда.
        public var maskBit: Int? {
            switch self {
            case .off:         return nil
            case .headTracked: return 0x01
            case .fixed:       return 0x02
            case .concert:     return 0x08
            case .theatre:     return 0x10
            case .game:        return 0x20
            }
        }
    }

    public static func parseSpatial(_ frame: Frame) -> SpatialMode? {
        guard let mode = frame.payload.first else { return nil }
        let head = frame.payload.count > 1 ? frame.payload[1] : 0
        // Порядок проверок — как у донора: голова выигрывает до поиска по
        // режиму, иначе `mode == 1` вернуло бы «фиксированный» и для неё.
        if head == 1 { return .headTracked }
        return SpatialMode.allCases.first { $0.wire.head == 0 && $0.wire.mode == mode } ?? .off
    }

    public static func encodeSetSpatial(_ mode: SpatialMode, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setSpatialAudio.rawValue,
                     operationID: operationID,
                     payload: [mode.wire.mode, mode.wire.head]))
    }

    /// Кодек, ответ `0x4029` и запись `0xF01C`: один байт — номер в списке.
    ///
    /// ⚠ Смена кодека **перезагружает наушники**: донор на записи показывает
    /// «Rebooting…» и ждёт переподключения. Это не наша догадка про устройство,
    /// а его собственное поведение, выраженное в чужом интерфейсе.
    ///
    /// Какие кодеки доступны модели — маска `highQualityAudio` из каталога;
    /// AAC есть всегда и бита не имеет.
    public enum Codec: UInt8, CaseIterable {
        case aac = 0
        case lhdc = 1
        case ldac = 2

        public var maskBit: Int? {
            switch self {
            case .aac:  return nil
            case .lhdc: return 0x02
            case .ldac: return 0x04
            }
        }

        /// Имя кодека не переводится: это название формата.
        public var title: String {
            switch self {
            case .aac:  return "AAC"
            case .lhdc: return "LHDC"
            case .ldac: return "LDAC"
            }
        }
    }

    public static func parseCodec(_ frame: Frame) -> Codec? {
        frame.payload.first.flatMap { Codec(rawValue: $0) }
    }

    public static func encodeSetCodec(_ codec: Codec, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setHighQualityAudio.rawValue,
                     operationID: operationID,
                     payload: [codec.rawValue]))
    }

    /// Одно устройство в списке пар. Адрес наружу не показывается **никогда**:
    /// он нужен только чтобы адресовать подключение, а на экране от него
    /// пользы нет. Имя показывается — это его собственные устройства.
    public struct DualDevice: Equatable {
        public let address: [UInt8]
        public let name: String
        /// Мы сами. Такую строку не отключают: отключишь — потеряешь связь,
        /// которой отключал.
        public let isSelf: Bool
        public let isConnected: Bool
    }

    /// Список пар, ответ `0x4028`.
    ///
    /// Формат записи: `[признаки][адрес 6][длина имени][имя]`. В признаках
    /// старший полубайт — «это мы», младший — «подключено». Длина имени берётся
    /// с маской `0x7f`: старший бит занят чем-то ещё, и донор его отбрасывает.
    ///
    /// Первые два байта payload донор не читает вовсе; счётчик записей — третий.
    /// Список приходит **страницами**: следующий запрос несёт число уже
    /// известных устройств, и так пока не перестанут появляться новые.
    public static func parseDualList(_ frame: Frame) -> [DualDevice] {
        let p = frame.payload
        guard p.count >= 3 else { return [] }
        var out: [DualDevice] = []
        var offset = 3
        for _ in 0..<Int(p[2]) {
            guard offset + 8 <= p.count else { break }
            let flags = p[offset]
            let length = Int(p[offset + 7] & 0x7F)
            guard offset + 8 + length <= p.count else { break }
            out.append(.init(address: Array(p[(offset + 1)..<(offset + 7)]),
                             name: String(decoding: p[(offset + 8)..<(offset + 8 + length)],
                                          as: UTF8.self),
                             isSelf: flags & 0xF0 != 0,
                             isConnected: flags & 0x0F != 0))
            offset += 8 + length
        }
        return out
    }

    /// Запрос очередной страницы списка: сколько устройств уже известно.
    public static func encodeRequestDualList(known: Int, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.dualList.rawValue, operationID: operationID,
                     payload: [UInt8(known & 0xFF)]))
    }

    public static func encodeSetDualEnabled(_ on: Bool, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setDualEnabled.rawValue, operationID: operationID,
                     payload: [on ? 1 : 0]))
    }

    public static func encodeSetDualConnect(address: [UInt8], connect: Bool,
                                            operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setDualConnect.rawValue, operationID: operationID,
                     payload: [connect ? 1 : 0] + address))
    }

    /// Персональный звук — выключатель профиля, построенного в телефонном
    /// приложении. Читается одним байтом, пишется одним байтом.
    ///
    /// Команда зависит от поставщика профиля, и его выбирает каталог:
    /// `0xC022`/`0xF015` у Mimi, `0xC05A`/`0xF05C` у Audiodo. Кодек знает
    /// форму, но не знает, кому её слать, — и это правильное разделение.
    public static func encodeSetPersonalSound(_ on: Bool, command: UInt16,
                                              operationID: UInt8) -> [UInt8] {
        encode(Frame(command: command, operationID: operationID, payload: [on ? 1 : 0]))
    }

    /// Куда адресован поиск устройства, запись `0xF002`.
    ///
    /// У донора это три ветки по имени модели, но числа в них не случайные:
    /// первый байт — идентификатор части устройства, тот же, что в ответе
    /// заряда (`2` левый, `3` правый, `6` полноразмерные). У B181 адресного
    /// байта нет вовсе, и это единственная настоящая особенность формы.
    /// Какие адреса есть у модели — говорит каталог, кодек их не выбирает.
    public enum RingTarget: Equatable, Hashable {
        /// Без адреса: один байт «звони / перестань».
        case whole
        /// С адресом части устройства.
        case component(UInt8)
    }

    public static func encodeRingDevice(_ target: RingTarget, on: Bool,
                                        operationID: UInt8) -> [UInt8] {
        let payload: [UInt8]
        switch target {
        case .whole:             payload = [on ? 1 : 0]
        case .component(let id): payload = [id, on ? 1 : 0]
        }
        return encode(Frame(command: Command.ringDevice.rawValue,
                            operationID: operationID, payload: payload))
    }

    /// Запись `0xF00A`: время в секундах эпохи, **big-endian** — в отличие от
    /// поля команды в заголовке и от чисел в эквалайзере, которые little-endian.
    public static func encodeSetTime(_ date: Date, operationID: UInt8) -> [UInt8] {
        let seconds = UInt32(date.timeIntervalSince1970)
        let payload: [UInt8] = [UInt8(seconds >> 24 & 0xFF), UInt8(seconds >> 16 & 0xFF),
                                UInt8(seconds >> 8 & 0xFF), UInt8(seconds & 0xFF)]
        return encode(Frame(command: Command.setUTCTime.rawValue, operationID: operationID, payload: payload))
    }

    /// Усиление баса, ответ `0x404E` и запись `0xF051`: `[включено, уровень]`.
    /// У B170 уровень на проводе вдвое больше показанного в интерфейсе;
    /// трёхступенчатая шкала — только у B189 и B186.
    public static func parseBassEnhance(_ frame: Frame) -> (enabled: Bool, level: Int)? {
        guard frame.payload.count >= 2 else { return nil }
        return (frame.payload[0] != 0, Int(frame.payload[1]) / 2)
    }

    public static func encodeSetBassEnhance(enabled: Bool, level: Int, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setBassEnhance.rawValue,
                     operationID: operationID,
                     payload: [enabled ? 1 : 0, UInt8(max(1, min(5, level)) * 2)]))
    }

    // MARK: - Жесты

    /// Одна строка раскладки управления: четыре байта на проводе. Первые три
    /// адресуют физический жест, четвёртый говорит, что он делает.
    ///
    /// Имена полей взяты из конфига донора (`deviceType`, `button`, `gesture`,
    /// `operation`). В его JS те же четыре байта названы `gestureDevice`,
    /// `gestureCommon`, `gestureType`, `gestureAction` — эти имена путают
    /// кнопку с типом жеста, и полагаться на них нельзя.
    ///
    /// Числа не разбираются на смыслы: у каждой модели свой набор кнопок,
    /// жестов и допустимых действий, и это данные, а не ветки в коде. Одна
    /// подсказка про действия: `0x0A` — переключение шумоподавления по кругу,
    /// а `0x14`, `0x15`, `0x16` — то же переключение с одним из трёх режимов,
    /// исключённым из круга (прозрачность, шумодав, выключено соответственно).
    public struct Gesture: Equatable {
        public let device: UInt8
        public let button: UInt8
        public let gesture: UInt8
        public let action: UInt8

        public init(device: UInt8, button: UInt8, gesture: UInt8, action: UInt8) {
            self.device = device
            self.button = button
            self.gesture = gesture
            self.action = action
        }
    }

    /// Состав круга, по которому жест гоняет шумоподавление.
    ///
    /// Порядок флажков взят из разметки всплывающего окна донора, а не с
    /// провода: прозрачность, шумоподавление, выключено. Меньше двух режимов
    /// в круге интерфейс оставить не даёт, поэтому кодов ровно четыре.
    public struct NoiseCycle: Equatable {
        public let transparency: Bool
        public let cancellation: Bool
        public let off: Bool

        public init(transparency: Bool, cancellation: Bool, off: Bool) {
            self.transparency = transparency
            self.cancellation = cancellation
            self.off = off
        }
    }

    /// Круг для действия жеста. `nil` — действие не про шумоподавление.
    ///
    /// Нужно потому, что каталог знает действие `0x0A`, а провод возвращает
    /// `0x16`: у B170 колесо на удержании стоит именно в круге без «выключено».
    /// Без этой пары интерфейс не узнаёт в ответе устройства то, что сам же
    /// перечислил как допустимое.
    public static func noiseCycle(_ action: UInt8) -> NoiseCycle? {
        switch action {
        case 0x0A: return .init(transparency: true,  cancellation: true,  off: true)
        case 0x14: return .init(transparency: false, cancellation: true,  off: true)
        case 0x15: return .init(transparency: true,  cancellation: false, off: true)
        case 0x16: return .init(transparency: true,  cancellation: true,  off: false)
        default:   return nil
        }
    }

    /// Обратно: код действия по составу круга. `nil` — такого круга не бывает,
    /// а не «мы его не нашли»: комбинаций всего четыре, остальные интерфейс
    /// донора собрать не даёт.
    public static func noiseAction(_ cycle: NoiseCycle) -> UInt8? {
        switch (cycle.transparency, cycle.cancellation, cycle.off) {
        case (true,  true,  true):  return 0x0A
        case (false, true,  true):  return 0x14
        case (true,  false, true):  return 0x15
        case (true,  true,  false): return 0x16
        default:                    return nil
        }
    }

    /// Ответ `0x4018`: `[число строк]` и дальше по четыре байта на строку.
    ///
    /// Шаг именно четыре. Догадка «четыре строки по три байта» на захвате B170
    /// сходилась по длине (13 = 1 + 4×3 = 1 + 3×4) и была неверной — совпадение
    /// длины тут ничего не доказывает, шаг взят из разбора у донора.
    public static func parseGestures(_ frame: Frame) -> [Gesture] {
        guard let count = frame.payload.first else { return [] }
        var result = [Gesture]()
        for i in 0..<Int(count) {
            let base = 1 + i * 4
            guard base + 3 < frame.payload.count else { break }
            result.append(.init(device: frame.payload[base],
                                button: frame.payload[base + 1],
                                gesture: frame.payload[base + 2],
                                action: frame.payload[base + 3]))
        }
        return result
    }

    // MARK: - Эквалайзер по полосам

    /// Одна полоса параметрического эквалайзера — тринадцать байт на проводе:
    /// `[тип фильтра][усиление][частота][добротность]`, три числа по четыре
    /// байта. Известные типы фильтра: `0` полка снизу, `1` пик, `2` полка
    /// сверху. Хранится сырым числом — вдруг устройство знает больше.
    public struct EQBand: Equatable {
        public let filterType: UInt8
        public let gain: Float
        public let frequency: Float
        public let quality: Float

        public init(filterType: UInt8, gain: Float, frequency: Float, quality: Float) {
            self.filterType = filterType
            self.gain = gain
            self.frequency = frequency
            self.quality = quality
        }
    }

    /// Кривая эквалайзера. Одна раскладка на две команды: у продвинутого
    /// (`0x404D` / `0xF050`) впереди лишний байт профиля, у пользовательского
    /// (`0x4044` / `0xF041`) его нет, дальше всё совпадает.
    ///
    /// `totalGain` донор считает как `-max(0, усиления)` — запас, чтобы сумма
    /// полос не ушла в клиппинг. Повторяем его арифметику, а не изобретаем.
    public struct EQCurve: Equatable {
        public let profile: UInt8?
        public let totalGain: Float
        public let bands: [EQBand]

        public init(profile: UInt8?, totalGain: Float, bands: [EQBand]) {
            self.profile = profile
            self.totalGain = totalGain
            self.bands = bands
        }

        /// Кривая с общим усилением по правилу донора.
        public init(profile: UInt8?, bands: [EQBand]) {
            self.init(profile: profile,
                      totalGain: -max(0, bands.map(\.gain).max() ?? 0),
                      bands: bands)
        }
    }

    /// Числа эквалайзера — IEEE-754 одинарной точности, **little-endian**.
    /// Донор пишет их big-endian и тут же разворачивает массив; результат тот
    /// же, а промежуточный шаг только путает.
    static func float32(_ bytes: ArraySlice<UInt8>) -> Float {
        let b = Array(bytes)
        guard b.count == 4 else { return 0 }
        return Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8
                              | UInt32(b[2]) << 16 | UInt32(b[3]) << 24)
    }

    static func float32(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF),
                UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24 & 0xFF)]
    }

    /// Есть ли у команды ведущий байт профиля. Списком, а не арифметикой по
    /// младшему байту: список видно глазами и он не подберёт чужую команду.
    static func carriesProfile(_ command: UInt16) -> Bool {
        [0xC04D, 0x404D, 0xF050, 0x7050].contains(command)
    }

    /// Разбирает `0x4044`, `0x404D` и собственные записи в них же.
    ///
    /// Число полос берётся из заголовка, а не из длины: устройство отвечает
    /// буфером постоянного размера на восемь полос и при пустой настройке
    /// присылает 109 или 110 нулевых байт. Ноль полос — это «не настроено»,
    /// а не «ответ пустой».
    ///
    /// Разворот чисел, который донор делает на чтении для крошечных значений
    /// (меньше денормализованного минимума), не повторяем: для усиления,
    /// частоты и добротности такие значения недостижимы.
    public static func parseEQCurve(_ frame: Frame) -> EQCurve? {
        let profiled = carriesProfile(frame.command)
        let head = profiled ? 2 : 1
        guard frame.payload.count >= head + 4 else { return nil }
        let count = Int(frame.payload[head - 1])
        let totalGain = float32(frame.payload[head..<head + 4])
        var bands = [EQBand]()
        for i in 0..<count {
            let base = head + 4 + i * 13
            guard base + 13 <= frame.payload.count else { break }
            bands.append(.init(filterType: frame.payload[base],
                               gain: float32(frame.payload[base + 1..<base + 5]),
                               frequency: float32(frame.payload[base + 5..<base + 9]),
                               quality: float32(frame.payload[base + 9..<base + 13])))
        }
        return EQCurve(profile: profiled ? frame.payload[0] : nil,
                       totalGain: totalGain, bands: bands)
    }

    static func eqPayload(_ curve: EQCurve, profiled: Bool) -> [UInt8] {
        var payload = [UInt8]()
        if profiled { payload.append(curve.profile ?? 0) }
        payload.append(UInt8(curve.bands.count))
        payload += float32(curve.totalGain)
        for band in curve.bands {
            payload.append(band.filterType)
            payload += float32(band.gain)
            payload += float32(band.frequency)
            payload += float32(band.quality)
        }
        return payload
    }

    /// Запись `0xF04F`: `[признак, 0x00]`. Донор шлёт выключение перед каждой
    /// записью пресета, не глядя на текущее состояние, — и это единственный
    /// известный способ выйти из продвинутого эквалайзера, который запись
    /// `0xF050` включает сама. Выключение проверено на железе; включение
    /// этим же кадром донор делает кнопкой «Advanced», на проводе не сверялось.
    public static func encodeSetAdvancedEQEnabled(_ enabled: Bool, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setAdvancedEQEnabled.rawValue,
                     operationID: operationID,
                     payload: [enabled ? 1 : 0, 0x00]))
    }

    /// Запись `0xF050`. Раскладка та же, что у чтения `0x404D`, но профиль
    /// донор пишет нулём, а спрашивает двести пятьдесят пятым — эту асимметрию
    /// оставляем на усмотрение вызывающего.
    public static func encodeSetAdvancedEQ(_ curve: EQCurve, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setAdvancedEQValue.rawValue, operationID: operationID,
                     payload: eqPayload(curve, profiled: true)))
    }

    /// Запись `0xF041`. Донор дописывает в хвост по три нуля на полосу, чего
    /// в раскладке чтения нет вовсе; повторяем как есть — расхождение может
    /// оказаться и форматом, и его небрежностью, проверить пока не на чем.
    public static func encodeSetCustomEQ(_ curve: EQCurve, operationID: UInt8) -> [UInt8] {
        let payload = eqPayload(curve, profiled: false)
            + [UInt8](repeating: 0, count: curve.bands.count * 3)
        return encode(Frame(command: Command.setCustomEQ.rawValue, operationID: operationID,
                            payload: payload))
    }

    /// Запись `0xF003`: та же строка, ровно одна, с ведущим счётчиком.
    /// Раскладка байтов совпадает с чтением, хотя по сигнатуре донорского
    /// `sendGestures(device, typeog, action, typebutton)` этого не видно:
    /// четвёртый её аргумент ложится во второй байт строки.
    public static func encodeSetGesture(_ gesture: Gesture, operationID: UInt8) -> [UInt8] {
        encode(Frame(command: Command.setGestures.rawValue,
                     operationID: operationID,
                     payload: [0x01, gesture.device, gesture.button, gesture.gesture, gesture.action]))
    }
}
