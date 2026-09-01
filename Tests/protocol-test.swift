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

        // Запись — два байта, второй всегда ноль. И записанное обязано читаться
        // обратно тем же разбором: у чтения и записи одно значение в payload[0].
        let eqSet = try! NothingProtocol.decode(
            NothingProtocol.encodeSetEqualiser(.treble, operationID: 4))
        check(eqSet.payload == [0x02, 0x00], "пресет пишется двумя байтами, второй ноль",
              eqSet.payload.map { String($0, radix: 16) }.joined(separator: " "))
        for preset in NothingProtocol.EqualiserPreset.allCases {
            let written = try! NothingProtocol.decode(
                NothingProtocol.encodeSetEqualiser(preset, operationID: 4))
            check(NothingProtocol.parseEqualiser(written) == preset,
                  "пресет \(preset) переживает запись и чтение")
        }
        // Шестёрка на странице выглядит пресетом, но им не является: та кнопка
        // шлёт включение продвинутого эквалайзера, а не 0xF010.
        check(NothingProtocol.EqualiserPreset(rawValue: 6) == nil,
              "«Advanced» пресетом не считается")

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

        // --- жесты: кадр целиком снят с устройства, три строки по четыре байта
        let gestureFrame = try! NothingProtocol.decode(
            bytes("55600118400d000d0306010716060a010b060a0701eaa9"))
        let gestures = NothingProtocol.parseGestures(gestureFrame)
        check(gestures.count == 3, "в раскладке B170 три строки", "\(gestures.count)")
        check(gestures == [.init(device: 6, button: 1, gesture: 7, action: 22),
                           .init(device: 6, button: 10, gesture: 1, action: 11),
                           .init(device: 6, button: 10, gesture: 7, action: 1)],
              "строки раскладки разбираются шагом четыре, а не три")

        // Обрезанный хвост не должен ни ронять разбор, ни выдумывать строки:
        // счётчик обещает три, байтов хватает на полторы.
        let truncated = NothingProtocol.Frame(command: 0x4018, operationID: 1,
                                              payload: bytes("0306010716060a"))
        check(NothingProtocol.parseGestures(truncated).count == 1,
              "недосказанная строка отбрасывается, а не достраивается мусором")

        // Раскладка записи совпадает с раскладкой чтения — это и есть то, что
        // легко потерять: у донора порядок аргументов функции записи другой,
        // и перенос его на провод даёт переставленные кнопку и тип жеста.
        let singlePress = NothingProtocol.Gesture(device: 6, button: 10, gesture: 1, action: 11)
        let written = try! NothingProtocol.decode(
            NothingProtocol.encodeSetGesture(singlePress, operationID: 3))
        check(written.payload == [0x01, 0x06, 0x0A, 0x01, 0x0B],
              "запись жеста кодируется со счётчиком впереди",
              written.payload.map { String($0, radix: 16) }.joined(separator: " "))
        check(NothingProtocol.parseGestures(written) == [singlePress],
              "записанная строка читается тем же разбором — раскладки совпадают")

        // --- продвинутый эквалайзер: payload целиком снят с устройства
        let advancedPayload = bytes("00080000000001000000000000"
            + "5c420000803f01000000000000dc420000803f010000000000005c430000803f"
            + "01000000000000dc430000803f01000000000000a5440000803f010000000000"
            + "404e450000803f01000000000040ce450000803f010000000000404e460000803f")
        check(advancedPayload.count == 110, "ответ 0x404D — 110 байт",
              "\(advancedPayload.count)")
        let advanced = NothingProtocol.parseEQCurve(
            .init(command: 0x404D, operationID: 1, payload: advancedPayload))
        check(advanced?.profile == 0, "профиль читается из ведущего байта")
        check(advanced?.bands.count == 8, "восемь полос",
              "\(advanced?.bands.count ?? -1)")
        check(advanced?.totalGain == 0, "общее усиление ноль")
        check(advanced?.bands.map(\.frequency) == [55, 110, 220, 440, 1320, 3300, 6600, 13200],
              "частоты полос разбираются как little-endian float32",
              "\(advanced?.bands.map(\.frequency) ?? [])")
        check(advanced?.bands.allSatisfy { $0.quality == 1 && $0.gain == 0 && $0.filterType == 1 } == true,
              "у всех полос добротность 1.0, усиление 0.0, фильтр «пик»")

        // Кадр от устройства обязан пересобираться байт в байт: иначе запись
        // отличалась бы от того, что оно само присылает.
        check(NothingProtocol.eqPayload(advanced!, profiled: true) == advancedPayload,
              "кривая пересобирается в тот же payload")

        // Пустая настройка приходит буфером постоянного размера, забитым
        // нулями. Ноль полос — это «не настроено», а не «ответ пустой»,
        // и разбор не должен ни падать, ни выдумывать восемь полос из нулей.
        let emptyCurve = NothingProtocol.parseEQCurve(
            .init(command: 0x4044, operationID: 1,
                  payload: [UInt8](repeating: 0, count: 109)))
        check(emptyCurve?.bands.isEmpty == true,
              "нулевой буфер читается как «полос нет», а не как восемь пустых")
        check(emptyCurve?.profile == nil,
              "у пользовательского эквалайзера байта профиля нет")

        // Общее усиление донор считает как минус наибольшее положительное.
        let curve = NothingProtocol.EQCurve(profile: 0, bands: [
            .init(filterType: 1, gain: 3, frequency: 980, quality: 0.7),
            .init(filterType: 2, gain: -2, frequency: 3500, quality: 1),
        ])
        check(curve.totalGain == -3, "общее усиление — минус наибольшее из положительных",
              "\(curve.totalGain)")
        let curveWritten = try! NothingProtocol.decode(
            NothingProtocol.encodeSetAdvancedEQ(curve, operationID: 5))
        check(NothingProtocol.parseEQCurve(curveWritten) == curve,
              "кривая переживает запись и чтение")
        check(curveWritten.payload.count == 2 + 4 + 2 * 13, "две полосы — тридцать два байта",
              "\(curveWritten.payload.count)")

        // 980 Гц в little-endian float32 — контрольное число, посчитанное
        // вручную: 0x44750000, младшим байтом вперёд.
        check(Array(curveWritten.payload[11..<15]) == bytes("00007544"),
              "частота кодируется младшим байтом вперёд",
              curveWritten.payload[11..<15].map { String(format: "%02x", $0) }.joined())

        // Пользовательскому донор дописывает по три нуля на полосу — в чтении
        // такого хвоста нет. Повторено сознательно, проверкой закреплено.
        let customWritten = try! NothingProtocol.decode(
            NothingProtocol.encodeSetCustomEQ(curve, operationID: 6))
        check(customWritten.payload.count == 1 + 4 + 2 * 13 + 2 * 3,
              "пользовательская запись длиннее на три байта с полосы",
              "\(customWritten.payload.count)")
        check(customWritten.payload.suffix(6).allSatisfy { $0 == 0 },
              "хвост пользовательской записи нулевой")

        // --- ожидаемый ответ на запрос и на запись
        check(NothingProtocol.Frame(command: 0xC007, operationID: 1).expectedReply == 0x4007,
              "запрос 0xC007 ждёт ответа 0x4007")
        check(NothingProtocol.Frame(command: 0xF00A, operationID: 10).expectedReply == 0x700A,
              "запись 0xF00A ждёт подтверждения 0x700A")
        check(NothingProtocol.Frame(command: 0xF003, operationID: 3).expectedReply == 0x7003,
              "запись жеста ждёт подтверждения 0x7003")

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
            .init(minFirmware: "1.0.0.0", maxFirmware: nil, flags: [.eq: 1], gestures: []),
            .init(minFirmware: "1.0.0.0", maxFirmware: nil, flags: [.eq: 2], gestures: []),
        ], sound: .neither)
        let picked = overlapping.bands.first { NothingCatalog.inBand("1.0.0.5", $0) }
        check(picked?.flags[.eq] == 1, "из двух подходящих полос берётся первая",
              "\(String(describing: picked?.flags[.eq]))")

        check(NothingCatalog.flags(model: "B157", firmware: "1.0.2.5")[.noiseReduction] == 1,
              "у B157 на 1.0.2.5 действует полоса *.*.2.0, стоящая в списке первой")
        check(NothingCatalog.flags(model: "B157", firmware: "1.0.1.79")[.noiseReduction] == 2,
              "у B157 на 1.0.1.79 — полоса постарше")

        identities()
        gestureTables()
        soundStyles()
    }

    /// Таблица опознания: ключ по трём байтам, имя, база и основа картинок.
    /// Проверки здесь сводят её с таблицей моделей — два независимых куска
    /// чужого кода, и расхождение между ними значит, что мы что-то поняли не так.
    static func identities() {
        let ids = NothingCatalog.identities
        check(ids.count == 63, "в таблице опознания 63 записи", "\(ids.count)")
        check(Set(ids.map(\.code)).count == ids.count, "коды опознания не повторяются")
        check(ids.allSatisfy { $0.code.count == 6 && $0.code == $0.code.uppercased() },
              "коды записаны шестью заглавными шестнадцатеричными знаками")

        // Опознание живого устройства: семь байт из кэша моста, ключ — три
        // последних. Кадр настоящий, снят 01.09.2026.
        let mine = NothingCatalog.identity(fastpair: bytes("03010003c19ecd"))
        check(mine?.base == "B170", "опознание 03010003c19ecd даёт B170",
              mine?.base ?? "не нашлось")
        check(mine?.artwork == "b170_black", "и чёрный цвет — цвет кодируется самой записью",
              mine?.artwork ?? "—")
        check(NothingCatalog.identity(fastpair: bytes("0301"))?.base == nil,
              "коротким байтам опознания соответствия нет, и разбор не падает")

        // Каждая база и каждая альтернатива обязаны существовать в таблице
        // моделей: это второй независимый кусок чужого кода.
        let known = Set(NothingCatalog.models.map(\.id))
        let strayBase = ids.map(\.base).filter { !known.contains($0) }
        check(strayBase.isEmpty, "все базы опознания есть в таблице моделей",
              strayBase.joined(separator: " "))
        let strayAlt = ids.compactMap(\.altBase).filter { !known.contains($0) }
        check(strayAlt.isEmpty, "все альтернативные базы есть в таблице моделей",
              strayAlt.joined(separator: " "))

        // И наоборот: ни одна модель конфига не осталась без опознания. Прямо
        // покрыто 19 моделей, ещё четыре — только через altBase; если однажды
        // altBase перестанут читать, эти четыре молча осиротеют.
        let covered = Set(ids.map(\.base)).union(ids.compactMap(\.altBase))
        check(covered == known, "опознание покрывает все 23 модели",
              known.subtracting(covered).sorted().joined(separator: " "))
        check(Set(ids.compactMap(\.altBase)) == ["B183", "B187", "B198", "B201"],
              "через altBase достижимы ровно четыре модели")

        // Основа имени картинок из базы НЕ выводится. У B173 картинки лежат
        // под номером базы, хотя altBase у неё B201, — а у прочих записей
        // с альтернативой наоборот. Проверка держит соблазн «оптимизировать»
        // хранение основы обратно в правило.
        let b173 = ids.first { $0.base == "B173" && $0.altBase == "B201" }
        check(b173?.artwork.hasPrefix("b173") == true,
              "у B173 картинки под номером базы, а не альтернативы",
              b173?.artwork ?? "—")
        let b183 = ids.first { $0.altBase == "B183" }
        check(b183?.artwork.hasPrefix("b183") == true,
              "а у B162 с альтернативой B183 — наоборот, под номером альтернативы",
              b183?.artwork ?? "—")
    }

    /// Раскладка жестов по моделям. Строится по конфигу устройства, а сверяется
    /// с разметкой страниц — это два независимых куска чужого кода, и сверка
    /// уже в генераторе. Здесь закрепляем результат: числа, провенанс и три
    /// строки, которые вернуло живое устройство.
    static func gestureTables() {
        let all = NothingCatalog.models.flatMap { $0.bands.flatMap(\.gestures) }
        check(all.count == 252, "в раскладках жестов 252 строки", "\(all.count)")
        let byEvidence = Dictionary(grouping: all, by: \.evidence.rawValue).mapValues(\.count)
        check(byEvidence == ["crossChecked": 203, "derived": 43, "wire": 6],
              "провенанс строк: 203 сверено, 43 выведено, 6 с провода", "\(byEvidence)")

        // Провод B170, 01.09.2026: ответ 0x4018 отдал три строки. Таблица на той
        // же прошивке обязана дать ровно их — ни одной лишней и ни одной меньше.
        let b170 = NothingCatalog.gestures(model: "B170", firmware: "1.0.1.81")
        // Payload как есть из лога; кадр вокруг него собираем сами — в захвате
        // записан именно payload, а не байты целиком.
        let onWire = NothingProtocol.parseGestures(
            .init(command: 0x4018, operationID: 1,
                  payload: bytes("0306010716060a010b060a0701")))
        check(onWire.count == 3, "захват 0x4018 разбирается в три строки", "\(onWire.count)")
        let fromTable = Set(b170.map { [$0.device, $0.button, $0.gesture.rawValue] })
        check(fromTable == Set(onWire.map { [$0.device, $0.button, $0.gesture] }),
              "таблица B170 совпадает со строками, пришедшими с провода")
        check(b170.allSatisfy { $0.evidence == .wire }, "и все три помечены проводом")

        // Действие с провода обязано найтись в списке допустимого. Наивно
        // сравнивать коды нельзя: колесо стоит в 0x16, а в списке 0x0A.
        let matched = onWire.allSatisfy { record in
            guard let slot = b170.first(where: {
                      $0.device == record.device && $0.button == record.button
                          && $0.gesture.rawValue == record.gesture }),
                  let action = NothingCatalog.GestureAction(wire: record.action)
            else { return false }
            return slot.actions.contains(action)
        }
        check(matched, "каждое действие с провода есть в списке своего слота")
        check(NothingCatalog.GestureAction(wire: 0x16) == .noiseControl,
              "код круга 0x16 приводится к шумоподавлению")
        check(NothingCatalog.GestureAction(rawValue: 0x16) == nil,
              "а сырым значением 0x16 в перечисление не входит — иначе круг стал бы действием")

        // Полосы прошивок. B157 — единственная модель, у которой раскладка
        // от прошивки зависит; если станет две, упадёт эта проверка.
        let stickNew = NothingCatalog.gestures(model: "B157", firmware: "1.0.2.5")
        let stickOld = NothingCatalog.gestures(model: "B157", firmware: "1.0.1.79")
        check(stickNew.contains { $0.actions.contains(.noiseControl) },
              "у B157 на полосе от *.*.2.0 шумоподавление в жестах есть")
        check(!stickOld.contains { $0.actions.contains(.noiseControl) },
              "а на полосе постарше его нет")
        let banded = NothingCatalog.models.filter {
            Set($0.bands.map { b in b.gestures.map { "\($0)" }.joined() }).count > 1
        }
        check(banded.map(\.id) == ["B157"], "и другой такой модели нет",
              banded.map(\.id).joined(separator: " "))

        // Циферблат корпуса. Конфиг объявляет его у пяти моделей, а страница
        // под него есть только у B189 — там строки сверены, у прочих выведены.
        let dial = NothingCatalog.models.flatMap { m in
            m.bands[0].gestures.filter { $0.device == 4 }.map { (m.id, $0) }
        }
        check(Set(dial.map(\.0)) == ["B172", "B173", "B187", "B189", "B201"],
              "циферблат корпуса заявлен у пяти моделей",
              Set(dial.map(\.0)).sorted().joined(separator: " "))
        check(dial.filter { $0.1.evidence == .crossChecked }.allSatisfy { $0.0 == "B189" },
              "сверен он только у B189 — у остальных страницы под него нет")

        // Модели без страницы достижимы только как altBase, второго источника
        // для них нет вовсе — ни одна их строка сверенной быть не может.
        for id in ["B183", "B187", "B198", "B201"] {
            let slots = NothingCatalog.models.first { $0.id == id }!.bands[0].gestures
            check(!slots.isEmpty && slots.allSatisfy { $0.evidence == .derived },
                  "у \(id) без страницы все строки помечены выведенными")
        }

        // Умолчание, если оно есть, обязано лежать в своём же списке.
        let strayDefault = all.filter { s in
            s.defaultAction.map { !s.actions.contains($0) } ?? false
        }
        check(strayDefault.isEmpty, "умолчание всегда есть в списке действий своего слота",
              "\(strayDefault.count)")

        // Круг шумоподавления: четыре кода и ни одного больше.
        check(NothingProtocol.noiseCycle(0x16) == .init(transparency: true,
                                                        cancellation: true, off: false),
              "0x16 — круг без «выключено»")
        check(NothingProtocol.noiseCycle(0x0B) == nil, "голосовой помощник кругом не является")
        check(NothingProtocol.noiseAction(.init(transparency: true, cancellation: true,
                                                off: false)) == 0x16,
              "и обратно тот же код")
        check(NothingProtocol.noiseAction(.init(transparency: false, cancellation: false,
                                                off: true)) == nil,
              "круга из одного режима не бывает — интерфейс донора его не собрать")
    }

    /// Пресеты и профили: чем модель управляет звучанием. Наборы дополняют
    /// друг друга, и проверки здесь держат именно это — плюс три места, где
    /// источники расходятся и расхождение названо.
    static func soundStyles() {
        let all = NothingCatalog.models
        var presets = 0, profiles = 0, neither = 0
        for m in all {
            switch m.sound {
            case .presets:  presets += 1
            case .profiles: profiles += 1
            case .neither:  neither += 1
            }
        }
        check((presets, profiles, neither) == (15, 7, 1),
              "15 моделей с пресетами, 7 с профилями, 1 без того и другого",
              "\(presets)/\(profiles)/\(neither)")

        // Профили и команда 0xF01D — два независимых куска чужого кода: набор
        // кнопок на странице и жёсткий список моделей внутри отправки. Сойтись
        // они обязаны, иначе одно из двух прочитано неверно.
        let withProfiles = Set(all.filter { if case .profiles = $0.sound { return true }
                                            else { return false } }.map(\.id))
        let canSend = Set(all.map(\.id).filter {
            NothingCatalog.supports(NothingCatalog.byCode[0xF01D]!, model: $0, firmware: "1.0.1.81")
        })
        check(withProfiles == ["B168", "B172", "B175", "B179", "B184", "B185", "B189"],
              "профили ровно у семи моделей", withProfiles.sorted().joined(separator: " "))
        check(canSend == withProfiles,
              "и это те же модели, которым разрешена 0xF01D",
              canSend.symmetricDifference(withProfiles).sorted().joined(separator: " "))

        // B187 — единственное место, где источники расходятся, и разойтись им
        // тут нечем: страницы у модели нет вовсе. Конфиг говорит «ноль
        // пресетов», жёсткий список профилей её не называет. Наследовать набор
        // базы нельзя — это supportId под другим именем.
        check(NothingCatalog.model("B187")?.sound == NothingCatalog.SoundStyle.neither,
              "у B187 не выбрано ни пресетов, ни профилей — и это честный ответ")

        // Dirac стоит у B185 в 7, а у остальных шести в 0. Соблазн «выровнять»
        // держится этой проверкой: подписи у них тоже разные.
        check(NothingCatalog.model("B185")?.sound
                == .profiles([.rock, .electronic, .pop, .vocals, .classical, .custom, .dirac]),
              "у B185 Dirac стоит в 7, а не в 0")
        check(NothingCatalog.model("B189")?.sound
                == .profiles([.rock, .electronic, .pop, .vocals, .classical, .custom]),
              "а у B189 никакого Dirac нет вовсе")

        // Пресеты: у всех пятёрка, у B181 четвёрка без своей кривой.
        check(NothingCatalog.model("B181")?.sound
                == .presets([.balanced, .voice, .treble, .bass]),
              "у B181 четыре пресета — своей кривой нет")
        check(NothingCatalog.model("B170")?.sound
                == .presets([.balanced, .voice, .treble, .bass, .custom]),
              "а у B170 пятёрка со своей кривой")

        // Значение 6 в двух семействах значит разное, и это не описка донора:
        // у профилей это настоящий 0xF01D («своя кривая»), у пресетов — кнопка
        // включения продвинутого эквалайзера, которая по проводу не идёт.
        check(NothingCatalog.SoundProfile.custom.rawValue == 6,
              "у профилей 6 — своя кривая")
        check(NothingProtocol.EqualiserPreset(rawValue: 6) == nil,
              "а среди пресетов значения 6 нет: там это переключатель, не пресет")
    }

    static func finish() {
        print(failures == 0 ? "\nвсе проверки прошли" : "\nпровалено: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
