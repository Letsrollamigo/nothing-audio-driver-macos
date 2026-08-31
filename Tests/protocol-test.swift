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

        // --- блок настроек: кадр, снятый с устройства
        let settingsFrame = NothingProtocol.Frame(
            command: 0x400E, operationID: 1,
            payload: bytes("0901010201070109010a010b000e0112011501"))
        let settings = NothingProtocol.parseSettings(settingsFrame)
        check(settings.count == 9, "блок настроек разбирается на девять записей", "\(settings.count)")
        check(settings[0x01] == 1, "детекция в ухе включена")
        check(settings[0x0b] == 0, "выключенная настройка читается как ноль")
        check(NothingProtocol.parseInEarDetection(settingsFrame) == true,
              "детекция ищется по идентификатору, а не по смещению")

        // Перестановка записей не должна ломать разбор — их парсер такое ломает.
        let reordered = NothingProtocol.Frame(command: 0x400E, operationID: 1,
                                              payload: [0x02, 0x0b, 0x00, 0x01, 0x01])
        check(NothingProtocol.parseInEarDetection(reordered) == true,
              "порядок записей в блоке настроек не важен")

        // --- пресет эквалайзера, снят с устройства
        let eq = NothingProtocol.Frame(command: 0x401F, operationID: 1, payload: [0x00])
        check(NothingProtocol.parseEqualiser(eq) == .balanced, "пресет эквалайзера разбирается")

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

        // --- каталог: словарь команд и таблица возможностей моделей
        catalog()

        finish()
    }

    /// Проверки каталога. Отдельно, потому что проверяют не разбор байтов,
    /// а согласованность таблицы — с железом, с кодеком и с самой собой.
    static func catalog() {
        let ops = NothingCatalog.operations
        check(ops.count == 84, "в словаре 84 команды", "\(ops.count)")
        check(Set(ops.map(\.code)).count == ops.count, "коды команд не повторяются")

        // Роль обязана следовать из старшего байта, иначе таблица врёт о себе.
        let roleMismatch = ops.filter {
            NothingProtocol.Frame(command: $0.code, operationID: 0).role != $0.role
        }
        check(roleMismatch.isEmpty, "роль в словаре совпадает с ролью по старшему байту",
              roleMismatch.map { String(format: "%04x", $0.code) }.joined(separator: " "))

        // У каждого запроса должен быть парный ответ. Записи в эту проверку не
        // входят: подтверждений 0x70NN в словаре нет вовсе, потому что донор их
        // не разбирает — он считает запись fire-and-forget. Провод показал
        // обратное (0xF00A → 0x700A), но отдельных строк это не требует:
        // код подтверждения выводится из кода записи арифметикой.
        let missing = ops.filter { $0.role == .request }
            .compactMap { op -> String? in
                let reply = NothingProtocol.Frame(command: op.code, operationID: 0).expectedReply
                return reply.flatMap { NothingCatalog.byCode[$0] } == nil
                    ? String(format: "%04x", op.code) : nil
            }
        check(missing.isEmpty, "у каждого запроса есть парный ответ", missing.joined(separator: " "))
        check(!ops.contains { $0.role == .ack },
              "подтверждений в словаре нет — донор их не разбирает, код выводится арифметикой")

        // Кодек знает часть команд по именам — они не должны разъехаться со
        // словарём. Два источника правды про одни и те же числа расходятся сами.
        let drift = NothingProtocol.Command.allCases.filter { NothingCatalog.byCode[$0.rawValue] == nil }
        check(drift.isEmpty, "коды в кодеке есть в словаре",
              drift.map { "\($0)" }.joined(separator: " "))

        // --- сверка таблицы с железом.
        // Всё, на что B170 ответил проводом, таблица обязана считать доступным;
        // всё, на что промолчал, — недоступным. Это единственная проверка,
        // где данные из чужого кода спорят с наблюдением, и выигрывает железо.
        let b170 = "B170", fw = "1.0.1.81"
        let contradictWire = ops.filter { $0.evidence == .wire }
            .filter { !NothingCatalog.supports($0, model: b170, firmware: fw) }
        check(contradictWire.isEmpty, "таблица не отрицает команд, на которые B170 ответил",
              contradictWire.map { $0.name }.joined(separator: " "))

        let contradictSilent = ops.filter { $0.evidence == .silent }
            .filter { NothingCatalog.supports($0, model: b170, firmware: fw) }
        check(contradictSilent.isEmpty, "таблица не обещает команд, на которые B170 промолчал",
              contradictSilent.map { $0.name }.joined(separator: " "))

        check(ops.contains { $0.evidence == .silent }, "молчание устройства зафиксировано в типе")

        // --- полосы прошивок: возможности зависят не только от модели.
        // У B170 персональный звук появился с *.*.1.75; на 1.0.1.74 его нет.
        check(NothingCatalog.flags(model: b170, firmware: fw)[.audiodo] == 1,
              "на 1.0.1.81 у B170 есть персональный звук")
        // Проверять на nil мало: nil получится и если полоса выбрана верно, и
        // если не выбрана ни одна. Спрашиваем положительно — сколько флагов
        // в старой полосе, — иначе проверка пройдёт при сломанном выборе.
        check(NothingCatalog.flags(model: b170, firmware: "1.0.1.74").count == 12,
              "на 1.0.1.74 у B170 берётся старая полоса — двенадцать возможностей",
              "\(NothingCatalog.flags(model: b170, firmware: "1.0.1.74").count)")
        check(NothingCatalog.flags(model: b170, firmware: "1.0.1.74")[.audiodo] == nil,
              "и персонального звука среди них ещё нет")
        // Границы полос включительные с обеих сторон: ровно на *.*.1.75 новая
        // полоса уже действует. При строгом сравнении проверка упадёт.
        check(NothingCatalog.flags(model: b170, firmware: "1.0.1.75")[.audiodo] == 1,
              "точное попадание в нижнюю границу полосы уже даёт новые возможности")
        check(NothingCatalog.flags(model: b170, firmware: "1.0.1.74")[.eq] != nil,
              "верхняя граница тоже включительна")

        // Пустая версия приходит с неготового устройства. Раньше на ней падало.
        check(NothingCatalog.flags(model: b170, firmware: "").isEmpty,
              "пустая версия не подходит ни к одной полосе и не роняет процесс")
        // Само сравнение пустую строку переживает: недостающие компоненты
        // считаются нулями, поэтому пустая версия оказывается самой старой.
        // До полос это не доходит — `inBand` отсекает раньше, как и донор.
        check(NothingCatalog.compare("", "1.0.0.0") < 0,
              "пустая версия сравнивается без падения и считается самой старой")

        // Подвох сравнения: звёздочка пропускает компонент у ОБЕИХ версий.
        check(NothingCatalog.compare("1.0.1.81", "*.*.1.75") > 0,
              "1.0.1.81 новее полосы *.*.1.75")
        check(NothingCatalog.compare("9.9.1.74", "*.*.1.75") < 0,
              "звёздочка пропускает старшие компоненты, а не считает их нулями")

        // --- пресеты эквалайзера и listening mode взаимно исключают друг друга.
        // Семь моделей вместо пресетов имеют режим прослушивания; ни одна модель
        // не может иметь оба, иначе интерфейс покажет две шкалы одного и того же.
        let presets = NothingCatalog.byCode[0xC01F]!, listening = NothingCatalog.byCode[0xC050]!
        let both = NothingCatalog.models.map(\.id).filter {
            NothingCatalog.supports(presets, model: $0, firmware: fw)
                && NothingCatalog.supports(listening, model: $0, firmware: fw)
        }
        check(both.isEmpty, "ни у одной модели нет и пресетов, и режима прослушивания",
              both.joined(separator: " "))

        // Гейт у записи режима прослушивания задан ранним `return` — условие в
        // коде донора выглядит обратным тому, что значит. Проверяем смысл.
        check(NothingCatalog.supports(NothingCatalog.byCode[0xF01D]!, model: "B189", firmware: fw),
              "B189 умеет писать режим прослушивания")
        check(!NothingCatalog.supports(NothingCatalog.byCode[0xF01D]!, model: b170, firmware: fw),
              "B170 режим прослушивания не пишет — у него пресеты")

        // В конфиге есть поле supportId, указывающее одну модель на другую, и
        // соблазн трактовать его как «возможности берутся оттуда» большой.
        // Сайт этого поля не читает нигде — проверено поиском по всем файлам, —
        // а модели, на которые оно указывает, оригиналу не равны: у B183 свой
        // набор пресетов эквалайзера, отличный от B162. Наследование дало бы
        // B183 чужое значение. Проверка держит эту дверь закрытой.
        check(NothingCatalog.flags(model: "B183", firmware: fw)[.eq]
                != NothingCatalog.flags(model: "B162", firmware: fw)[.eq],
              "B183 не наследует эквалайзер у B162 — у каждой модели свой набор")
        check(NothingCatalog.flags(model: "B183", firmware: fw)[.eq] != nil,
              "у B183 набор при этом есть, а не пуст")

        // Чтение режима шумоподавления оставлено `.always` осознанно. У донора
        // оно закрыто гейтом сразу по модели И прошивке: B157 читает режим
        // только на полосе x.x.2.x. Наши четыре вида условий такого не
        // выражают, и из двух возможных приближений `.always` дешевле —
        // лишний кадр устройство молча проигнорирует, а запрет отнял бы у B157
        // работающую команду. Замена на `.flag(.ancLevel)` выглядит очевидной
        // и НЕВЕРНА: у B174 и B189 этого ключа в конфиге нет вовсе, а режим
        // они читают. Проверка держит оба соблазна закрытыми.
        check(NothingCatalog.byCode[0xC01E]!.requires == .always,
              "чтение режима доступно всем — гейт B157 по прошивке не выражается условием")
        for id in ["B174", "B189", "B157"] {
            check(NothingCatalog.supports(NothingCatalog.byCode[0xC01E]!, model: id, firmware: fw),
                  "\(id) читает режим шумоподавления")
        }
        check(NothingCatalog.flags(model: "B174", firmware: fw)[.ancLevel] == nil,
              "у B174 при этом ancLevel в конфиге нет — гейтить по нему нельзя")

        check(NothingCatalog.models.count == 23, "в таблице 23 модели",
              "\(NothingCatalog.models.count)")

        // Итог по B170 зафиксирован числом: 52 из 84. Спецификация до сверки
        // с кодом донора обещала 59 — она гейтила часть команд по флагу конфига
        // и пропускала жёсткие списки моделей. Например, микрофонные режимы
        // 0xC064/0xF065 закрыты флагом superMic ровно так же, как 0xC05E,
        // но в спецификации закрыт был только второй.
        check(NothingCatalog.operations(model: b170, firmware: fw).count == 52,
              "B170 доступно 52 команды из 84",
              "\(NothingCatalog.operations(model: b170, firmware: fw).count)")

        // Донор разрешает B185 ЧИТАТЬ усиление баса, но не писать: в списке
        // моделей у чтения B185 есть, у записи нет. Похоже на их опечатку, но
        // проверить не на чем — модели у нас нет, поэтому повторяем как есть,
        // а не «исправляем» вслепую.
        let bassRead = NothingCatalog.byCode[0xC04E]!, bassWrite = NothingCatalog.byCode[0xF051]!
        check(NothingCatalog.supports(bassRead, model: "B185", firmware: fw),
              "B185 читает усиление баса")
        check(!NothingCatalog.supports(bassWrite, model: "B185", firmware: fw),
              "B185 усиление баса не пишет — асимметрия донора сохранена")

        // Полосы перечислены в порядке донора, и порядок значим: берётся первая
        // подходящая, а не самая узкая или самая новая. На реальных данных это
        // не проверить — у настоящих моделей полосы не пересекаются, и правило
        // можно сломать незаметно. Поэтому пересечение делаем искусственно.
        let overlapping = NothingCatalog.Model(id: "TEST", bands: [
            .init(minFirmware: "1.0.0.0", maxFirmware: nil, flags: [.eq: 1]),
            .init(minFirmware: "1.0.0.0", maxFirmware: nil, flags: [.eq: 2]),
        ])
        let picked = overlapping.bands.first { NothingCatalog.inBand("1.0.0.5", $0) }
        check(picked?.flags[.eq] == 1, "из двух подходящих полос берётся первая",
              "\(String(describing: picked?.flags[.eq]))")

        check(NothingCatalog.flags(model: "B157", firmware: "1.0.2.5")[.noiseReduction] == 1,
              "у B157 на 1.0.2.5 действует полоса *.*.2.0, стоящая в списке первой")
        check(NothingCatalog.flags(model: "B157", firmware: "1.0.1.79")[.noiseReduction] == 2,
              "у B157 на 1.0.1.79 — полоса постарше")
    }

    static func finish() {
        print(failures == 0 ? "\nвсе проверки прошли" : "\nпровалено: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
