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

    public enum Command: UInt16 {
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
        case setBassEnhance       = 0xF051
        case setUTCTime           = 0xF00A
        case ringDevice           = 0xF002
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

    public struct ListeningState: Equatable {
        public enum Mode: UInt8 { case noiseCancellation = 1, transparency = 2, off = 5 }
        public enum Strength: UInt8 { case high = 0, mid = 1, low = 2, adaptive = 3 }
        public let mode: Mode
        public let strength: Strength?
    }

    /// Ответ `0x401E`. Байт 1 — режим, байт 3 — сила шумоподавления;
    /// сила осмысленна только в режиме шумоподавления.
    public static func parseListening(_ frame: Frame) -> ListeningState? {
        guard frame.payload.count >= 4, let mode = ListeningState.Mode(rawValue: frame.payload[1]) else { return nil }
        let strength = ListeningState.Strength(rawValue: frame.payload[3])
        return ListeningState(mode: mode, strength: mode == .noiseCancellation ? strength : nil)
    }

    /// Запись `0xF00F`. Кодирование уровней взято из наблюдаемого обмена:
    /// значение режима лежит во втором байте, первый и третий постоянны.
    public static func encodeSetANC(mode: ListeningState.Mode,
                                   strength: ListeningState.Strength?,
                                   operationID: UInt8) -> [UInt8] {
        let value: UInt8
        switch (mode, strength) {
        case (.transparency, _):            value = 0x07
        case (.off, _):                     value = 0x05
        case (.noiseCancellation, .high):   value = 0x03
        case (.noiseCancellation, .mid):    value = 0x01
        case (.noiseCancellation, .low):    value = 0x02
        case (.noiseCancellation, _):       value = 0x04     // адаптивный
        }
        return encode(Frame(command: Command.setANC.rawValue,
                            operationID: operationID,
                            payload: [0x01, value, 0x00]))
    }
}
