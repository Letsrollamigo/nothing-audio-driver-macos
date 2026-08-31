import Foundation

// Проверка протокольного слоя на кадрах, записанных с живого устройства
// (Nothing Headphone (1), прошивка 1.0.1.81). Железо для запуска не нужно.

@main
struct ProtocolTest {
    static var failures = 0

    static func check(_ condition: Bool, _ what: String, _ detail: String = "") {
        if condition {
            print("ок    \(what)")
        } else {
            failures += 1
            print("ПЛОХО \(what)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map {
            let i = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[i...hex.index(i, offsetBy: 1)], radix: 16)!
        }
    }

    static func main() {
        // --- кадр и контрольная сумма, кадры настоящие
        let batteryRequest = NothingProtocol.encode(
            .init(command: 0xC007, operationID: 1))
        check(batteryRequest == bytes("55600107c0000001acdf"),
              "запрос заряда кодируется байт-в-байт как у устройства",
              batteryRequest.map { String(format: "%02x", $0) }.joined())

        let firmwareRequest = NothingProtocol.encode(.init(command: 0xC042, operationID: 3))
        check(firmwareRequest == bytes("55600142c0000003e0d1"), "запрос прошивки кодируется верно")

        // --- разбор ответов
        let realBattery = try! NothingProtocol.decode(bytes("55600107400300010106558bb5"))
        check(realBattery.role == .response, "роль ответа определяется по старшему байту")
        check(realBattery.operationID == 1, "идентификатор операции отзеркален")
        let parsed = NothingProtocol.parseBattery(realBattery)
        check(parsed?.readings.count == 1, "в ответе одно устройство")
        check(parsed?.readings.first?.component == .stereo, "тип устройства — полноразмерные")
        check(parsed?.readings.first?.percent == 85, "заряд 85 %",
              String(describing: parsed?.readings.first?.percent))
        check(parsed?.readings.first?.charging == false, "зарядка не идёт")

        let firmware = try! NothingProtocol.decode(bytes("5560014240080003312e302e312e3831ba96"))
        check(NothingProtocol.parseFirmware(firmware) == "1.0.1.81", "прошивка разбирается в строку")

        let anc = try! NothingProtocol.decode(bytes("5560011e4006000e0105000204004a7a"))
        check(NothingProtocol.parseListening(anc) == .off,
              "режим прослушивания читается из payload[1]", String(describing: NothingProtocol.parseListening(anc)))

        // Перестановка уровней шумоподавления — ошибка, которую легко не заметить:
        // проверяем КАЖДОЕ значение провода, а не одно удобное.
        let wire: [(NothingProtocol.ListeningMode, UInt8)] = [
            (.ancHigh, 0x01), (.ancMid, 0x02), (.ancLow, 0x03),
            (.ancAdaptive, 0x04), (.off, 0x05), (.transparency, 0x07),
        ]
        for (mode, value) in wire {
            let encoded = try! NothingProtocol.decode(NothingProtocol.encodeSetANC(mode, operationID: 1))
            check(encoded.payload == [0x01, value, 0x00],
                  "запись режима \(mode) даёт 0x\(String(value, radix: 16))",
                  encoded.payload.map { String($0, radix: 16) }.joined(separator: " "))
            let readBack = NothingProtocol.Frame(command: 0x401E, operationID: 1, payload: [0x01, value, 0x00, 0x00])
            check(NothingProtocol.parseListening(readBack) == mode,
                  "чтение 0x\(String(value, radix: 16)) возвращает \(mode)")
        }

        // --- детекция в ухе: признак в payload[2], не в payload[0]
        let inEar = NothingProtocol.Frame(command: 0x400E, operationID: 1, payload: [0x01, 0x01, 0x01])
        check(NothingProtocol.parseInEarDetection(inEar) == true, "детекция в ухе читается из payload[2]")
        let inEarOff = NothingProtocol.Frame(command: 0x400E, operationID: 1, payload: [0x01, 0x01, 0x00])
        check(NothingProtocol.parseInEarDetection(inEarOff) == false, "выключенная детекция читается верно")

        // --- время: big-endian, в отличие от всего остального в протоколе
        let timeFrame = try! NothingProtocol.decode(
            NothingProtocol.encodeSetTime(Date(timeIntervalSince1970: 0x6A955E13), operationID: 10))
        check(timeFrame.payload == [0x6A, 0x95, 0x5E, 0x13],
              "время кодируется big-endian",
              timeFrame.payload.map { String($0, radix: 16) }.joined(separator: " "))

        // --- усиление баса: у B170 уровень на проводе вдвое больше показанного
        let bass = NothingProtocol.Frame(command: 0x404E, operationID: 1, payload: [0x01, 0x06])
        check(NothingProtocol.parseBassEnhance(bass)?.level == 3, "уровень баса делится на два при чтении")
        let bassSet = try! NothingProtocol.decode(
            NothingProtocol.encodeSetBassEnhance(enabled: true, level: 3, operationID: 2))
        check(bassSet.payload == [0x01, 0x06], "уровень баса умножается на два при записи")

        // --- ожидаемый ответ на запрос и на запись
        check(NothingProtocol.Frame(command: 0xC007, operationID: 1).expectedReply == 0x4007,
              "запрос 0xC007 ждёт ответа 0x4007")
        check(NothingProtocol.Frame(command: 0xF00A, operationID: 10).expectedReply == 0x700A,
              "запись 0xF00A ждёт подтверждения 0x700A")

        // --- целостность
        var corrupted = bytes("55600107400300010106558bb5")
        corrupted[10] ^= 0xFF
        do {
            _ = try NothingProtocol.decode(corrupted)
            check(false, "испорченный кадр должен отвергаться по контрольной сумме")
        } catch {
            check(true, "испорченный кадр отвергается по контрольной сумме")
        }

        // --- нарезка потока: RFCOMM склеивает и режет доставки
        let glued = bytes("55600107400300010106558bb5") + bytes("5560011f4001000200dc77")
        let both = NothingProtocol.split(glued)
        check(both.frames.count == 2 && both.rest.isEmpty, "два склеенных кадра разбираются раздельно")

        let cut = Array(glued.prefix(20))
        let partial = NothingProtocol.split(cut)
        check(partial.frames.count == 1 && !partial.rest.isEmpty,
              "разрезанный кадр ждёт продолжения, а не теряется")

        let noise = bytes("aabbcc") + bytes("55600107400300010106558bb5")
        check(NothingProtocol.split(noise).frames.count == 1, "мусор перед кадром пропускается")

        finish()
    }

    static func finish() {
        print(failures == 0 ? "\nвсе проверки прошли" : "\nпровалено: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
