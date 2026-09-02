// Файл собран генератором и правится только через него.
//
// Генератор в репозиторий не входит: он разбирает исходники чужого проекта
// под AGPL-3.0 и требует локальной копии их сайта. Здесь лежит результат —
// числа протокола и возможности моделей, выраженные нашей структурой.
//
// Словарь команд и таблица возможностей моделей. Кодек живёт отдельно, в
// NothingProtocol.swift: он умеет байты и ничего не знает о моделях, а каталог
// знает, что кому можно слать, и ничего не знает о байтах.
//
// Различия моделей — данные, а не ветки в коде. Ветвление по модели прямо в
// разборе один раз уже стоило нам перепутанных уровней шумоподавления.

import Foundation

public enum NothingCatalog {

    /// Откуда взято знание. Физически доступна одна модель, B170, поэтому
    /// провод подтверждает только её; всё прочее выведено чтением чужого
    /// кода и может оказаться неверным.
    public enum Evidence: String {
        /// Спрошено у B170 и получен ответ.
        case wire
        /// Спрошено у B170 и ответа не было. Неподдерживаемое устройство
        /// молчит, а не отвечает отказом, — это сильнее догадки по конфигу.
        case silent
        /// Два независимых источника в чужом проекте сказали одно и то же:
        /// конфиг устройства и разметка страницы модели. Устройства нет,
        /// но и списать это на опечатку в одном месте уже нельзя. Бывает
        /// только у раскладки жестов — у команд второго источника нет.
        case crossChecked
        /// Не проверялось. Выведено из кода донора.
        case derived
    }

    /// Флаг конфига модели. Здесь только то, что меняет протокол: разрешает
    /// команду или меняет формат поля. Оформление интерфейса не включено.
    public enum Flag: String, CaseIterable {
        case adapterVolume
        case advancedEq
        case advancedEqTotalGain
        case ancLevel
        case audiodo
        case buttonPosition
        case callTransparency
        case deviceType
        case dualConnection
        case earDetection
        case earTipFitTest
        case eq
        case findDevice
        case highQualityAudio
        case longPowerMode
        case lowLagMode
        case magicButton
        case mimi
        case mutuallyExclusive
        case noiseReduction
        case personalizedAnc
        case serialNumber
        case smartKnob
        case spatialAudio
        case superMic
        case supportLeakageProtection
        case ultraBass
        case ultraBassType
        case utcTime
        case walkieTalkieMode
    }

    /// Условие, при котором команда вообще имеет смысл.
    public enum Requirement: Equatable {
        case always
        case flag(Flag)
        /// Жёсткий список моделей в коде донора; в конфиге таких списков нет.
        case onlyModels([String])
        case exceptModels([String])
    }

    public struct Op {
        public let code: UInt16
        public let name: String
        public let role: NothingProtocol.Frame.Role
        public let requires: Requirement
        public let evidence: Evidence
    }

    /// Полный словарь: 84 команд.
    public static let operations: [Op] = [
        .init(code: 0x4007, name: "battery", role: .response, requires: .always, evidence: .wire),
        .init(code: 0x400E, name: "inEar", role: .response, requires: .exceptModels(["B174", "B175", "B185", "B186", "B189"]), evidence: .wire),
        .init(code: 0x4017, name: "ledCaseColor", role: .response, requires: .onlyModels(["B181"]), evidence: .derived),
        .init(code: 0x4018, name: "gestures", role: .response, requires: .always, evidence: .wire),
        .init(code: 0x401E, name: "anc", role: .response, requires: .always, evidence: .wire),
        .init(code: 0x401F, name: "eq", role: .response, requires: .exceptModels(["B168", "B172", "B175", "B179", "B184", "B185", "B189"]), evidence: .wire),
        .init(code: 0x4020, name: "personalizedANC", role: .response, requires: .onlyModels(["B155"]), evidence: .silent),
        .init(code: 0x4022, name: "mimiEnable", role: .response, requires: .flag(.mimi), evidence: .silent),
        .init(code: 0x4027, name: "dualEnable", role: .response, requires: .flag(.dualConnection), evidence: .wire),
        .init(code: 0x4028, name: "dualList", role: .response, requires: .flag(.dualConnection), evidence: .derived),
        .init(code: 0x4029, name: "highQualityAudio", role: .response, requires: .flag(.highQualityAudio), evidence: .wire),
        .init(code: 0x4041, name: "latency", role: .response, requires: .always, evidence: .wire),
        .init(code: 0x4042, name: "firmware", role: .response, requires: .always, evidence: .wire),
        .init(code: 0x4044, name: "customEQ", role: .response, requires: .exceptModels(["B181"]), evidence: .wire),
        .init(code: 0x404C, name: "advancedEQ", role: .response, requires: .always, evidence: .wire),
        .init(code: 0x404D, name: "advancedEQValue", role: .response, requires: .always, evidence: .wire),
        .init(code: 0x404E, name: "enhancedBass", role: .response, requires: .onlyModels(["B162", "B164", "B168", "B170", "B171", "B172", "B173", "B179", "B184", "B185", "B186", "B189"]), evidence: .wire),
        .init(code: 0x404F, name: "spatialAudio", role: .response, requires: .flag(.spatialAudio), evidence: .wire),
        .init(code: 0x4050, name: "listeningMode", role: .response, requires: .onlyModels(["B168", "B172", "B175", "B179", "B184", "B185", "B189"]), evidence: .derived),
        .init(code: 0x405A, name: "audiodoProfileOn", role: .response, requires: .flag(.audiodo), evidence: .wire),
        .init(code: 0x405E, name: "superMicEnable", role: .response, requires: .flag(.superMic), evidence: .derived),
        .init(code: 0x405F, name: "callTransparencyEnable", role: .response, requires: .flag(.callTransparency), evidence: .derived),
        .init(code: 0x4060, name: "walkieTalkieMode", role: .response, requires: .flag(.walkieTalkieMode), evidence: .derived),
        .init(code: 0x4064, name: "micMode", role: .response, requires: .flag(.superMic), evidence: .derived),
        .init(code: 0x4067, name: "longPowerMode", role: .response, requires: .flag(.longPowerMode), evidence: .derived),
        .init(code: 0x4071, name: "antiLeakageMode", role: .response, requires: .flag(.supportLeakageProtection), evidence: .derived),
        .init(code: 0xC007, name: "battery", role: .request, requires: .always, evidence: .wire),
        .init(code: 0xC00E, name: "inEar", role: .request, requires: .exceptModels(["B174", "B175", "B185", "B186", "B189"]), evidence: .wire),
        .init(code: 0xC017, name: "ledCaseColor", role: .request, requires: .onlyModels(["B181"]), evidence: .derived),
        .init(code: 0xC018, name: "gestures", role: .request, requires: .always, evidence: .wire),
        .init(code: 0xC01E, name: "anc", role: .request, requires: .always, evidence: .wire),
        .init(code: 0xC01F, name: "eq", role: .request, requires: .exceptModels(["B168", "B172", "B175", "B179", "B184", "B185", "B189"]), evidence: .wire),
        .init(code: 0xC020, name: "personalizedANC", role: .request, requires: .onlyModels(["B155"]), evidence: .silent),
        .init(code: 0xC022, name: "mimiEnable", role: .request, requires: .flag(.mimi), evidence: .silent),
        .init(code: 0xC027, name: "dualEnable", role: .request, requires: .flag(.dualConnection), evidence: .wire),
        .init(code: 0xC028, name: "dualList", role: .request, requires: .flag(.dualConnection), evidence: .wire),
        .init(code: 0xC029, name: "highQualityAudio", role: .request, requires: .flag(.highQualityAudio), evidence: .wire),
        .init(code: 0xC041, name: "latency", role: .request, requires: .always, evidence: .wire),
        .init(code: 0xC042, name: "firmware", role: .request, requires: .always, evidence: .wire),
        .init(code: 0xC044, name: "customEQ", role: .request, requires: .exceptModels(["B181"]), evidence: .wire),
        .init(code: 0xC04C, name: "advancedEQ", role: .request, requires: .always, evidence: .wire),
        .init(code: 0xC04D, name: "advancedEQValue", role: .request, requires: .always, evidence: .wire),
        .init(code: 0xC04E, name: "enhancedBass", role: .request, requires: .onlyModels(["B162", "B164", "B168", "B170", "B171", "B172", "B173", "B179", "B184", "B185", "B186", "B189"]), evidence: .wire),
        .init(code: 0xC04F, name: "spatialAudio", role: .request, requires: .flag(.spatialAudio), evidence: .wire),
        .init(code: 0xC050, name: "listeningMode", role: .request, requires: .onlyModels(["B168", "B172", "B175", "B179", "B184", "B185", "B189"]), evidence: .derived),
        .init(code: 0xC05A, name: "audiodoProfileOn", role: .request, requires: .flag(.audiodo), evidence: .wire),
        .init(code: 0xC05E, name: "superMicEnable", role: .request, requires: .flag(.superMic), evidence: .derived),
        .init(code: 0xC05F, name: "callTransparencyEnable", role: .request, requires: .flag(.callTransparency), evidence: .derived),
        .init(code: 0xC060, name: "walkieTalkieMode", role: .request, requires: .flag(.walkieTalkieMode), evidence: .derived),
        .init(code: 0xC064, name: "micMode", role: .request, requires: .flag(.superMic), evidence: .derived),
        .init(code: 0xC067, name: "longPowerMode", role: .request, requires: .flag(.longPowerMode), evidence: .derived),
        .init(code: 0xC071, name: "antiLeakageMode", role: .request, requires: .flag(.supportLeakageProtection), evidence: .derived),
        .init(code: 0xE001, name: "battery", role: .push, requires: .always, evidence: .derived),
        .init(code: 0xE003, name: "anc", role: .push, requires: .always, evidence: .derived),
        .init(code: 0xE00D, name: "earFitTest", role: .push, requires: .onlyModels(["B155", "B162", "B171", "B172", "B173", "B179", "B184"]), evidence: .derived),
        .init(code: 0xE00E, name: "dualDeviceEvent", role: .push, requires: .always, evidence: .derived),
        .init(code: 0xE019, name: "audiodoStatusPush", role: .push, requires: .flag(.audiodo), evidence: .derived),
        .init(code: 0xF002, name: "ringDevice", role: .write, requires: .always, evidence: .derived),
        .init(code: 0xF003, name: "gestures", role: .write, requires: .always, evidence: .wire),
        .init(code: 0xF004, name: "inEar", role: .write, requires: .exceptModels(["B174", "B175", "B185", "B186", "B189"]), evidence: .derived),
        .init(code: 0xF00A, name: "utcTime", role: .write, requires: .exceptModels(["B181"]), evidence: .wire),
        .init(code: 0xF00D, name: "ledCaseColor", role: .write, requires: .onlyModels(["B181"]), evidence: .derived),
        .init(code: 0xF00F, name: "anc", role: .write, requires: .always, evidence: .derived),
        .init(code: 0xF010, name: "eq", role: .write, requires: .exceptModels(["B168", "B172", "B175", "B179", "B184", "B185", "B189"]), evidence: .wire),
        .init(code: 0xF011, name: "personalizedANC", role: .write, requires: .onlyModels(["B155"]), evidence: .derived),
        .init(code: 0xF014, name: "earFitTest", role: .write, requires: .onlyModels(["B155", "B162", "B171", "B172", "B173", "B179", "B184"]), evidence: .derived),
        .init(code: 0xF015, name: "mimiEnable", role: .write, requires: .flag(.mimi), evidence: .derived),
        .init(code: 0xF01A, name: "dualEnable", role: .write, requires: .flag(.dualConnection), evidence: .derived),
        .init(code: 0xF01B, name: "dualConnect", role: .write, requires: .flag(.dualConnection), evidence: .derived),
        .init(code: 0xF01C, name: "highQualityAudio", role: .write, requires: .flag(.highQualityAudio), evidence: .derived),
        .init(code: 0xF01D, name: "listeningMode", role: .write, requires: .onlyModels(["B168", "B172", "B175", "B179", "B184", "B185", "B189"]), evidence: .derived),
        .init(code: 0xF040, name: "latency", role: .write, requires: .always, evidence: .derived),
        .init(code: 0xF041, name: "customEQ", role: .write, requires: .exceptModels(["B181"]), evidence: .derived),
        .init(code: 0xF04F, name: "advancedEQEnabled", role: .write, requires: .always, evidence: .derived),
        .init(code: 0xF050, name: "advancedEQValue", role: .write, requires: .always, evidence: .wire),
        .init(code: 0xF051, name: "enhancedBass", role: .write, requires: .onlyModels(["B162", "B164", "B168", "B170", "B171", "B172", "B173", "B179", "B184", "B186", "B189"]), evidence: .wire),
        .init(code: 0xF052, name: "spatialAudio", role: .write, requires: .flag(.spatialAudio), evidence: .derived),
        .init(code: 0xF05C, name: "audiodoProfileOn", role: .write, requires: .flag(.audiodo), evidence: .derived),
        .init(code: 0xF05F, name: "superMicEnable", role: .write, requires: .flag(.superMic), evidence: .derived),
        .init(code: 0xF060, name: "callTransparencyEnable", role: .write, requires: .flag(.callTransparency), evidence: .derived),
        .init(code: 0xF061, name: "walkieTalkieMode", role: .write, requires: .flag(.walkieTalkieMode), evidence: .derived),
        .init(code: 0xF065, name: "micMode", role: .write, requires: .flag(.superMic), evidence: .derived),
        .init(code: 0xF068, name: "longPowerMode", role: .write, requires: .flag(.longPowerMode), evidence: .derived),
        .init(code: 0xF075, name: "antiLeakageMode", role: .write, requires: .flag(.supportLeakageProtection), evidence: .derived),
    ]

    public static let byCode: [UInt16: Op] =
        Dictionary(uniqueKeysWithValues: operations.map { ($0.code, $0) })

    // MARK: - Модели

    /// Физический жест. Номера протокольные, имена наши.
    public enum GestureKind: UInt8 {
        case singlePress = 1
        case doublePress = 2
        case triplePress = 3
        case slide = 5
        case pressHold = 7
        case doublePressHold = 9
        case rotate = 10
        case pinchBoth = 11
    }

    /// Действие, которое можно повесить на жест. Номера протокольные.
    ///
    /// Кодов 20, 21 и 22 здесь нет намеренно: это то же `noiseControl`, но с
    /// одним режимом, выброшенным из круга. Состав круга разбирает
    /// `NothingProtocol.noiseCycle`, а сюда такое значение приводит
    /// инициализатор `init(wire:)` — без него разбор реального ответа
    /// спотыкается на первом же устройстве: у B170 колесо стоит именно в 22.
    public enum GestureAction: UInt8 {
        case noAction = 1
        case playPause = 2
        case answerCall = 3
        case skipBack = 8
        case skipForward = 9
        case noiseControl = 10
        case voiceAssistant = 11
        case lowLagMode = 17
        case volumeUp = 18
        case volumeDown = 19
        case volumeControl = 23
        case cameraShutter = 24
        case answerCallAndMute = 25
        case hangUp = 26
        case spatialAudio = 27
        case micMute = 29
        case news = 31
        case radio = 32
        case essentialSpace = 33
        case eqPreset = 34
        case ultraBass = 35
        case trebleEnhance = 36
        case recording = 37

        /// Действие, пришедшее с провода.
        public init?(wire raw: UInt8) {
            self.init(rawValue: (20...22).contains(raw) ? 10 : raw)
        }
    }

    /// Физический орган управления — для моделей, у которых на устройстве
    /// их несколько и номера кнопки мало: у B170 колесо и кнопка, у B175
    /// ещё ползунок. Там, где орган один, его никто не называет и поле
    /// пустое; у циферблата корпуса орган называет сам номер устройства 4.
    public enum Control: String {
        case button, roller, slider
    }

    /// Одна строка раскладки: что на этом устройстве, этой кнопке и этом жесте
    /// вообще можно выбрать. Ровно те четыре байта, которыми обмениваются
    /// `0x4018` и `0xF003`, плюс список допустимого.
    public struct GestureSlot {
        /// 2 и 3 — левый и правый вкладыш, 4 — циферблат корпуса,
        /// 6 — наушники целиком. Конфиг перечисляет у вкладышей только 2;
        /// вторую сторону подтверждает топология JS и провод.
        public let device: UInt8
        public let button: UInt8
        public let gesture: GestureKind
        public let actions: [GestureAction]
        /// Значение с завода. У донора рядом лежат ещё варианты для телефона
        /// Nothing и для каждой стороны отдельно — их не переносим: на macOS
        /// первый бессмыслен, а вторые нужны интерфейсу, а не протоколу.
        public let defaultAction: GestureAction?
        /// Какой орган это физически. Есть только у моделей с несколькими
        /// органами на одном номере устройства; выводится из второго
        /// источника, поэтому у моделей без страницы всегда пуст — даже
        /// когда номера кнопок совпадают с моделью, у которой орган назван.
        public let control: Control?
        public let evidence: Evidence
    }


    /// Полоса прошивок: набор возможностей действует не для модели целиком,
    /// а для диапазона версий. У B170, например, персональный звук появился
    /// только с *.*.1.75 — на более старой прошивке команды просто нет.
    public struct Band {
        public let minFirmware: String?
        public let maxFirmware: String?
        public let flags: [Flag: Int]
        /// Раскладка жестов той же полосы. Полоса одна на оба: и флаги,
        /// и жесты читаются из одной записи конфига. Единственная модель,
        /// у которой они по полосам расходятся, — B157: шумоподавление
        /// в жестах есть только на полосе от *.*.2.0.
        public let gestures: [GestureSlot]
    }

    /// Профиль звучания — то, чем управляют семь моделей вместо пресетов
    /// эквалайзера. Команда `0xF01D`; у донора она зовётся `setListeningMode`,
    /// и это не тот «режим прослушивания», что в `NothingProtocol.ListeningMode`
    /// — там шумоподавление. Название в чужом коде занято дважды, у нас нет.
    ///
    /// `dirac` и `diracOpteo` — не опечатка: у B185 профиль Dirac стоит в 7,
    /// у остальных Dirac OPTEO в 0, и подписи у них тоже разные.
    public enum SoundProfile: UInt8 {
        case diracOpteo = 0
        case rock = 1
        case electronic = 2
        case pop = 3
        case vocals = 4
        case classical = 5
        case custom = 6
        case dirac = 7
    }

    /// Чем модель управляет звучанием. Наборы дополняют друг друга: ни одна
    /// модель не знает оба.
    public enum SoundStyle: Equatable {
        /// Пресеты эквалайзера, команда `0xF01F`.
        case presets([NothingProtocol.EqualiserPreset])
        /// Профили звучания, команда `0xF01D`.
        case profiles([SoundProfile])
        /// Ни того, ни другого. Так вышло у одной модели, B187: конфиг
        /// объявляет ноль пресетов, а в жёсткий список моделей с профилями
        /// её не внесли. Своей страницы у неё нет, достижима она только как
        /// altBase и тогда работает под номером базы. Подставить сюда набор
        /// базы было бы наследованием по альтернативе — тем самым, из-за
        /// которого не читается supportId.
        case neither
    }


    public struct Model {
        public let id: String
        public let bands: [Band]
        /// Пресеты или профили. Полосой прошивки не управляется: набор
        /// кнопок задан разметкой страницы, а она у модели одна.
        public let sound: SoundStyle
    }

    /// 23 моделей.
    public static let models: [Model] = [
        .init(id: "B181", bands: [
            .init(minFirmware: nil, maxFirmware: "*.*.1.74", flags: [.ancLevel: 53, .buttonPosition: 4, .dualConnection: 0, .eq: 15, .findDevice: 1, .lowLagMode: 0, .serialNumber: 0, .utcTime: 0], gestures: [
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
            ]),
            .init(minFirmware: "*.*.1.75", maxFirmware: "*.*.1.85", flags: [.ancLevel: 53, .buttonPosition: 4, .dualConnection: 0, .eq: 15, .findDevice: 1, .serialNumber: 0, .utcTime: 0], gestures: [
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
            ]),
            .init(minFirmware: "*.*.1.86", maxFirmware: nil, flags: [.ancLevel: 53, .buttonPosition: 4, .dualConnection: 0, .eq: 15, .findDevice: 1, .serialNumber: 0, .utcTime: 0], gestures: [
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass])),
        .init(id: "B157", bands: [
            .init(minFirmware: "*.*.2.0", maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -11, .ancLevel: 33, .buttonPosition: 4, .dualConnection: 0, .noiseReduction: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
            .init(minFirmware: nil, maxFirmware: "*.*.1.79", flags: [.ancLevel: 0, .buttonPosition: 4, .dualConnection: 0, .noiseReduction: 2], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
            .init(minFirmware: "*.*.1.80", maxFirmware: "*.*.1.999", flags: [.advancedEq: 1, .advancedEqTotalGain: -11, .ancLevel: 0, .buttonPosition: 4, .dualConnection: 0, .noiseReduction: 2], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B155", bands: [
            .init(minFirmware: nil, maxFirmware: "*.*.1.94", flags: [.advancedEq: 0, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 4, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 2, .mimi: 1, .personalizedAnc: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
            .init(minFirmware: "*.*.1.95", maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 4, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 2, .mimi: 1, .personalizedAnc: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B162", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 4, .ultraBass: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B171", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 4, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 7, .mimi: 1, .ultraBass: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B163", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 55, .buttonPosition: 2, .dualConnection: 0], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.playPause, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.playPause, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B164", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 3, .deviceType: 6, .dualConnection: 1, .earDetection: 0, .spatialAudio: 6, .ultraBass: 1], gestures: [
                .init(device: 6, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 6, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 6, button: 1, gesture: .pressHold, actions: [.noiseControl], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B168", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 49, .buttonPosition: 4, .dualConnection: 1, .eq: 0, .ultraBass: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .profiles([.diracOpteo, .rock, .electronic, .pop, .vocals, .classical, .custom])),
        .init(id: "B172", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 0, .highQualityAudio: 4, .smartKnob: 1, .spatialAudio: 6, .ultraBass: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 4, button: 1, gesture: .singlePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .triplePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .rotate, actions: [.noAction, .volumeControl], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 9, gesture: .doublePress, actions: [.noAction, .answerCall, .answerCallAndMute], defaultAction: nil, control: nil, evidence: .derived),
                .init(device: 4, button: 9, gesture: .triplePress, actions: [.noAction, .hangUp], defaultAction: nil, control: nil, evidence: .derived),
            ]),
        ], sound: .profiles([.diracOpteo, .rock, .electronic, .pop, .vocals, .classical, .custom])),
        .init(id: "B174", bands: [
            .init(minFirmware: nil, maxFirmware: "1.0.1.26", flags: [.advancedEq: 1, .buttonPosition: 2, .dualConnection: 1, .earDetection: 0, .eq: 31, .ultraBass: 0], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
            .init(minFirmware: "1.0.1.27", maxFirmware: "1.0.1.27", flags: [.adapterVolume: 1, .advancedEq: 1, .buttonPosition: 2, .dualConnection: 1, .earDetection: 0, .eq: 31, .ultraBass: 0], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
            .init(minFirmware: "1.0.1.28", maxFirmware: nil, flags: [.advancedEq: 1, .buttonPosition: 2, .dualConnection: 1, .earDetection: 0, .eq: 31, .ultraBass: 0], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B170", bands: [
            .init(minFirmware: nil, maxFirmware: "*.*.1.74", flags: [.advancedEq: 1, .ancLevel: 63, .deviceType: 6, .dualConnection: 1, .earDetection: 1, .eq: 31, .findDevice: 1, .highQualityAudio: 4, .magicButton: 1, .mutuallyExclusive: 1, .spatialAudio: 7, .ultraBass: 1], gestures: [
                .init(device: 6, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: .roller, evidence: .wire),
                .init(device: 6, button: 10, gesture: .singlePress, actions: [.noAction, .noiseControl, .voiceAssistant, .spatialAudio, .micMute, .news, .radio, .eqPreset], defaultAction: .voiceAssistant, control: .button, evidence: .wire),
                .init(device: 6, button: 10, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .spatialAudio, .micMute, .news, .radio, .essentialSpace, .eqPreset], defaultAction: .noAction, control: .button, evidence: .wire),
            ]),
            .init(minFirmware: "*.*.1.75", maxFirmware: nil, flags: [.advancedEq: 1, .ancLevel: 63, .audiodo: 1, .deviceType: 6, .dualConnection: 1, .earDetection: 1, .eq: 31, .findDevice: 1, .highQualityAudio: 4, .magicButton: 1, .mutuallyExclusive: 1, .spatialAudio: 7, .ultraBass: 1], gestures: [
                .init(device: 6, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: .roller, evidence: .wire),
                .init(device: 6, button: 10, gesture: .singlePress, actions: [.noAction, .noiseControl, .voiceAssistant, .spatialAudio, .micMute, .news, .radio, .eqPreset], defaultAction: .voiceAssistant, control: .button, evidence: .wire),
                .init(device: 6, button: 10, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .spatialAudio, .micMute, .news, .radio, .essentialSpace, .eqPreset], defaultAction: .noAction, control: .button, evidence: .wire),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B175", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .audiodo: 1, .deviceType: 6, .dualConnection: 1, .earDetection: 0, .findDevice: 1, .highQualityAudio: 4, .spatialAudio: 28, .ultraBass: 0], gestures: [
                .init(device: 6, button: 1, gesture: .pressHold, actions: [.noiseControl], defaultAction: .noiseControl, control: .roller, evidence: .crossChecked),
                .init(device: 6, button: 5, gesture: .singlePress, actions: [.ultraBass, .trebleEnhance], defaultAction: .ultraBass, control: .slider, evidence: .crossChecked),
                .init(device: 6, button: 10, gesture: .singlePress, actions: [.noAction, .noiseControl, .voiceAssistant, .spatialAudio, .micMute, .news], defaultAction: .voiceAssistant, control: .button, evidence: .crossChecked),
                .init(device: 6, button: 10, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .spatialAudio, .micMute, .news, .essentialSpace], defaultAction: .noAction, control: .button, evidence: .crossChecked),
            ]),
        ], sound: .profiles([.diracOpteo, .rock, .electronic, .pop, .vocals, .classical, .custom])),
        .init(id: "B185", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 49, .buttonPosition: 4, .dualConnection: 1, .earDetection: 0, .eq: 0, .ultraBass: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .profiles([.rock, .electronic, .pop, .vocals, .classical, .custom, .dirac])),
        .init(id: "B179", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .spatialAudio: 6, .ultraBass: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .profiles([.diracOpteo, .rock, .electronic, .pop, .vocals, .classical, .custom])),
        .init(id: "B184", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .audiodo: 1, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 4, .spatialAudio: 6, .ultraBass: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .profiles([.diracOpteo, .rock, .electronic, .pop, .vocals, .classical, .custom])),
        .init(id: "B173", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .audiodo: 1, .buttonPosition: 1, .callTransparency: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .superMic: 1, .ultraBass: 1, .walkieTalkieMode: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 4, button: 1, gesture: .pressHold, actions: [.noAction, .voiceAssistant, .essentialSpace], defaultAction: .voiceAssistant, control: nil, evidence: .derived),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B183", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .ultraBass: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .derived),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .derived),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noiseControl, control: nil, evidence: .derived),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noiseControl, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .derived),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B187", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 0, .dualConnection: 1, .earTipFitTest: 1, .eq: 0, .highQualityAudio: 4, .smartKnob: 1, .spatialAudio: 6, .ultraBass: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .derived),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .derived),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .derived),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .news], defaultAction: .noiseControl, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .singlePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .triplePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .rotate, actions: [.noAction, .volumeControl], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 9, gesture: .doublePress, actions: [.noAction, .answerCall, .answerCallAndMute], defaultAction: nil, control: nil, evidence: .derived),
                .init(device: 4, button: 9, gesture: .triplePress, actions: [.noAction, .hangUp], defaultAction: nil, control: nil, evidence: .derived),
            ]),
        ], sound: .neither),
        .init(id: "B186", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .ancLevel: 63, .audiodo: 0, .deviceType: 6, .dualConnection: 1, .earDetection: 0, .eq: 31, .findDevice: 1, .highQualityAudio: 4, .magicButton: 1, .mutuallyExclusive: 0, .spatialAudio: 28, .ultraBass: 1, .ultraBassType: 3], gestures: [
                .init(device: 6, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: .roller, evidence: .crossChecked),
                .init(device: 6, button: 10, gesture: .singlePress, actions: [.noAction, .noiseControl, .voiceAssistant, .cameraShutter, .micMute, .news, .radio, .eqPreset], defaultAction: .voiceAssistant, control: .button, evidence: .crossChecked),
                .init(device: 6, button: 10, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .micMute, .news, .radio, .essentialSpace, .eqPreset], defaultAction: .noAction, control: .button, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B198", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .ancLevel: 63, .audiodo: 0, .deviceType: 6, .dualConnection: 1, .earDetection: 0, .eq: 31, .findDevice: 1, .highQualityAudio: 4, .magicButton: 1, .mutuallyExclusive: 0, .spatialAudio: 28, .ultraBass: 1, .ultraBassType: 3], gestures: [
                .init(device: 6, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl], defaultAction: .noiseControl, control: nil, evidence: .derived),
                .init(device: 6, button: 10, gesture: .singlePress, actions: [.noAction, .noiseControl, .voiceAssistant, .cameraShutter, .micMute, .news, .radio, .eqPreset], defaultAction: .voiceAssistant, control: nil, evidence: .derived),
                .init(device: 6, button: 10, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .micMute, .news, .radio, .essentialSpace, .eqPreset], defaultAction: .noAction, control: nil, evidence: .derived),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B201", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .audiodo: 1, .buttonPosition: 1, .callTransparency: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .superMic: 1, .ultraBass: 1, .walkieTalkieMode: 1], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .derived),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .derived),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news], defaultAction: .noiseControl, control: nil, evidence: .derived),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news], defaultAction: .noiseControl, control: nil, evidence: .derived),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .derived),
                .init(device: 4, button: 1, gesture: .pressHold, actions: [.noAction, .voiceAssistant, .essentialSpace], defaultAction: .voiceAssistant, control: nil, evidence: .derived),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B190", bands: [
            .init(minFirmware: nil, maxFirmware: "1.0.1.36", flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .ultraBass: 0, .walkieTalkieMode: 0], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news, .recording], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pinchBoth, actions: [.noAction, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news, .recording], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pinchBoth, actions: [.noAction, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
            ]),
            .init(minFirmware: "1.0.1.37", maxFirmware: "1.0.1.60", flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .ultraBass: 0, .walkieTalkieMode: 0], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news, .recording], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pinchBoth, actions: [.noAction, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news, .recording], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pinchBoth, actions: [.noAction, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
            ]),
            .init(minFirmware: "1.0.1.61", maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .ultraBass: 0, .walkieTalkieMode: 0], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news, .recording], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pinchBoth, actions: [.noAction, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .micMute, .news, .recording], defaultAction: .noiseControl, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .noiseControl, .voiceAssistant, .volumeUp, .volumeDown, .news, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pinchBoth, actions: [.noAction, .recording], defaultAction: .recording, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .presets([.balanced, .voice, .treble, .bass, .custom])),
        .init(id: "B189", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 0, .buttonPosition: 2, .dualConnection: 1, .earDetection: 0, .highQualityAudio: 4, .longPowerMode: 1, .spatialAudio: 6, .supportLeakageProtection: 1, .ultraBass: 1, .ultraBassType: 3], gestures: [
                .init(device: 2, button: 1, gesture: .doublePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .pressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 2, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipForward, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .triplePress, actions: [.noAction, .skipBack, .skipForward, .voiceAssistant, .news], defaultAction: .skipBack, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .pressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 3, button: 1, gesture: .doublePressHold, actions: [.noAction, .voiceAssistant, .volumeUp, .volumeDown, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 4, button: 1, gesture: .singlePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 4, button: 1, gesture: .doublePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 4, button: 1, gesture: .triplePress, actions: [.noAction, .playPause, .skipBack, .skipForward, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 4, button: 1, gesture: .pressHold, actions: [.noAction, .voiceAssistant, .lowLagMode, .news], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 4, button: 1, gesture: .rotate, actions: [.noAction, .volumeControl], defaultAction: .noAction, control: nil, evidence: .crossChecked),
                .init(device: 4, button: 9, gesture: .doublePress, actions: [.noAction, .answerCall, .answerCallAndMute], defaultAction: nil, control: nil, evidence: .crossChecked),
                .init(device: 4, button: 9, gesture: .triplePress, actions: [.noAction, .hangUp], defaultAction: nil, control: nil, evidence: .crossChecked),
            ]),
        ], sound: .profiles([.rock, .electronic, .pop, .vocals, .classical, .custom])),
    ]

    // MARK: - Опознание устройства

    /// Запись таблицы опознания. Канал опознания отдаёт семь байт, и последние
    /// три — ключ сюда. Одна модель встречается столько раз, сколько у неё
    /// цветов: отдельного поля цвета нет нигде, цвет — это то, какая запись
    /// совпала.
    ///
    /// `artwork` — основа имени файлов с рендерами: к ней дописывается
    /// `_left`, `_right`, `_case`, `_duo` и `.webp`. Из `base` она НЕ выводится:
    /// у двух записей картинки лежат под номером базы, а не альтернативы,
    /// у остальных двенадцати наоборот. Поэтому хранится как есть.
    ///
    /// Сами файлы в репозиторий и бандл не входят и входить не должны — они
    /// лежат в скачанной копии сайта на машине пользователя.
    public struct Identity {
        public let code: String
        public let name: String
        public let base: String
        /// Второй возможный номер модели для того же железа. Чем именно
        /// выбирается один из двух, из кода донора не видно; не угадывать.
        public let altBase: String?
        public let artwork: String
    }

    /// 63 записей опознания.
    public static let identities: [Identity] = [
        .init(code: "DEE8C0", name: "Ear (2)", base: "B155", altBase: nil, artwork: "b155_black"),
        .init(code: "ACC520", name: "Ear (2)", base: "B155", altBase: nil, artwork: "b155_white"),
        .init(code: "1016DD", name: "Ear (Stick)", base: "B157", altBase: nil, artwork: "b157_white"),
        .init(code: "03464E", name: "Nothing Ear (a)", base: "B162", altBase: nil, artwork: "b162_black"),
        .init(code: "5E3FBC", name: "Nothing Ear (a)", base: "B162", altBase: nil, artwork: "b162_white"),
        .init(code: "8B6380", name: "Nothing Ear (a)", base: "B162", altBase: nil, artwork: "b162_yellow"),
        .init(code: "C34F3B", name: "Nothing Ear (a)", base: "B162", altBase: "B183", artwork: "b183_black"),
        .init(code: "404D6D", name: "Nothing Ear (a)", base: "B162", altBase: "B183", artwork: "b183_white"),
        .init(code: "839E9A", name: "Nothing Ear (a)", base: "B162", altBase: "B183", artwork: "b183_yellow"),
        .init(code: "ADD2C4", name: "Buds Pro", base: "B163", altBase: nil, artwork: "b163_black"),
        .init(code: "5F8F82", name: "Buds Pro", base: "B163", altBase: nil, artwork: "b163_orange"),
        .init(code: "2EB1CA", name: "Buds Pro", base: "B163", altBase: nil, artwork: "b163_white"),
        .init(code: "AE35FD", name: "Neckband Pro", base: "B164", altBase: nil, artwork: "b164_black"),
        .init(code: "4DFC4A", name: "Neckband Pro", base: "B164", altBase: nil, artwork: "b164_orange"),
        .init(code: "26C190", name: "Neckband Pro", base: "B164", altBase: nil, artwork: "b164_white"),
        .init(code: "150A27", name: "CMF Buds", base: "B168", altBase: nil, artwork: "b168_black"),
        .init(code: "D35E18", name: "CMF Buds", base: "B168", altBase: nil, artwork: "b168_orange"),
        .init(code: "ACCE54", name: "CMF Buds", base: "B168", altBase: nil, artwork: "b168_white"),
        .init(code: "C19ECD", name: "Nothing Headphone (1)", base: "B170", altBase: nil, artwork: "b170_black"),
        .init(code: "2D6FDA", name: "Nothing Headphone (1)", base: "B170", altBase: nil, artwork: "b170_grey"),
        .init(code: "A20444", name: "Nothing Ear", base: "B171", altBase: nil, artwork: "b171_black"),
        .init(code: "FEB1C7", name: "Nothing Ear", base: "B171", altBase: nil, artwork: "b171_white"),
        .init(code: "F29566", name: "CMF Buds Pro 2", base: "B172", altBase: nil, artwork: "b172_black"),
        .init(code: "2B353E", name: "CMF Buds Pro 2", base: "B172", altBase: nil, artwork: "b172_blue"),
        .init(code: "A7B220", name: "CMF Buds Pro 2", base: "B172", altBase: nil, artwork: "b172_orange"),
        .init(code: "CA36A6", name: "CMF Buds Pro 2", base: "B172", altBase: nil, artwork: "b172_white"),
        .init(code: "2F45F5", name: "CMF Buds Pro 2", base: "B172", altBase: "B187", artwork: "b187_black"),
        .init(code: "0F1A4F", name: "CMF Buds Pro 2", base: "B172", altBase: "B187", artwork: "b187_blue"),
        .init(code: "1253C0", name: "CMF Buds Pro 2", base: "B172", altBase: "B187", artwork: "b187_orange"),
        .init(code: "E1BE45", name: "CMF Buds Pro 2", base: "B172", altBase: "B187", artwork: "b187_white"),
        .init(code: "7D46E5", name: "Nothing Ear (3)", base: "B173", altBase: "B201", artwork: "b173_black"),
        .init(code: "C1EBFD", name: "Nothing Ear (3)", base: "B173", altBase: "B201", artwork: "b173_white"),
        .init(code: "CC3444", name: "Nothing Ear (open)", base: "B174", altBase: nil, artwork: "b174_blue"),
        .init(code: "FC3AAF", name: "Nothing Ear (open)", base: "B174", altBase: nil, artwork: "b174_white"),
        .init(code: "1EFB39", name: "CMF Headphone Pro", base: "B175", altBase: nil, artwork: "b175_black"),
        .init(code: "563DA5", name: "CMF Headphone Pro", base: "B175", altBase: nil, artwork: "b175_green"),
        .init(code: "73C9EB", name: "CMF Headphone Pro", base: "B175", altBase: nil, artwork: "b175_white"),
        .init(code: "19EF24", name: "CMF Buds 2", base: "B179", altBase: nil, artwork: "b179_black"),
        .init(code: "FF2AB0", name: "CMF Buds 2", base: "B179", altBase: nil, artwork: "b179_green"),
        .init(code: "D9AB5D", name: "CMF Buds 2", base: "B179", altBase: nil, artwork: "b179_orange"),
        .init(code: "624011", name: "Nothing ear (1)", base: "B181", altBase: nil, artwork: "b181_black"),
        .init(code: "31D53D", name: "Nothing ear (1)", base: "B181", altBase: nil, artwork: "b181_white"),
        .init(code: "5C587F", name: "CMF Buds 2 Plus", base: "B184", altBase: nil, artwork: "b184_blue"),
        .init(code: "4AEB6E", name: "CMF Buds 2 Plus", base: "B184", altBase: nil, artwork: "b184_white"),
        .init(code: "70F8E3", name: "CMF Buds 2a", base: "B185", altBase: nil, artwork: "b185_black"),
        .init(code: "509CAE", name: "CMF Buds 2a", base: "B185", altBase: nil, artwork: "b185_orange"),
        .init(code: "ED5412", name: "CMF Buds 2a", base: "B185", altBase: nil, artwork: "b185_white"),
        .init(code: "BFD53B", name: "Nothing Headphone (a)", base: "B186", altBase: nil, artwork: "b186_black"),
        .init(code: "98D02B", name: "Nothing Headphone (a)", base: "B186", altBase: nil, artwork: "b186_pink"),
        .init(code: "DE8953", name: "Nothing Headphone (a)", base: "B186", altBase: nil, artwork: "b186_white"),
        .init(code: "6F6C71", name: "Nothing Headphone (a)", base: "B186", altBase: "B198", artwork: "b198_black"),
        .init(code: "A292C6", name: "Nothing Headphone (a)", base: "B186", altBase: "B198", artwork: "b198_pink"),
        .init(code: "810478", name: "Nothing Headphone (a)", base: "B186", altBase: "B198", artwork: "b198_white"),
        .init(code: "97EF75", name: "Nothing Headphone (a)", base: "B186", altBase: "B198", artwork: "b198_yellow"),
        .init(code: "79B3A9", name: "Nothing Headphone (a)", base: "B186", altBase: "B198", artwork: "b198_yellow"),
        .init(code: "DA1280", name: "CMF Clip Pro", base: "B189", altBase: nil, artwork: "b189_black"),
        .init(code: "8F28ED", name: "CMF Clip Pro", base: "B189", altBase: nil, artwork: "b189_blue"),
        .init(code: "E6673A", name: "CMF Clip Pro", base: "B189", altBase: nil, artwork: "b189_orange"),
        .init(code: "DCD2CB", name: "CMF Clip Pro", base: "B189", altBase: nil, artwork: "b189_white"),
        .init(code: "E9C3BE", name: "Nothing Ear (3a)", base: "B190", altBase: nil, artwork: "b190_black"),
        .init(code: "148887", name: "Nothing Ear (3a)", base: "B190", altBase: nil, artwork: "b190_pink"),
        .init(code: "7B2328", name: "Nothing Ear (3a)", base: "B190", altBase: nil, artwork: "b190_white"),
        .init(code: "DB45D3", name: "Nothing Ear (3a)", base: "B190", altBase: nil, artwork: "b190_yellow"),
    ]

    /// Опознание по семи байтам канала опознания: ключ — последние три,
    /// записанные заглавным гексом.
    public static func identity(fastpair bytes: [UInt8]) -> Identity? {
        guard bytes.count >= 3 else { return nil }
        let code = bytes.suffix(3).map { String(format: "%02X", $0) }.joined()
        return identities.first { $0.code == code }
    }

    // MARK: - Разрешение возможностей

    /// Сравнение версий прошивки с подвохом: `*` в любой позиции пропускает
    /// компонент у ОБЕИХ сравниваемых версий, а не только у шаблона. Поэтому
    /// `*.*.1.75` против `1.0.1.81` сравнивает лишь два последних числа.
    /// Воспроизводим как есть — иначе разойдёмся с тем, что видит устройство.
    static func compare(_ a: String, _ b: String) -> Int {
        // `first ?? ""`, а не `[0]`: у пустой строки Swift даёт пустой массив,
        // и обращение по индексу роняет процесс. Пустая версия приходит с
        // устройства по-настоящему — `parseFirmware` отдаёт "" на занулённом
        // ответе 0x4042, а такой ответ приходит на неготовое устройство.
        let x = (a.split(separator: "-").first ?? "").split(separator: ".")
        let y = (b.split(separator: "-").first ?? "").split(separator: ".")
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? String(x[i]) : "0"
            let q = i < y.count ? String(y[i]) : "0"
            if p == "*" || q == "*" { continue }
            guard let n = Int(p), let m = Int(q) else { continue }
            if n != m { return n > m ? 1 : -1 }
        }
        return 0
    }

    static func inBand(_ version: String, _ band: Band) -> Bool {
        if band.minFirmware == nil && band.maxFirmware == nil { return true }
        // Пустая версия при заданных границах не подходит никуда — так же
        // решает донор (`isInVersion`: `if (currentEmpty) return false`).
        // Иначе полоса выбралась бы первая попавшаяся.
        if version.isEmpty { return false }
        if let lo = band.minFirmware, compare(version, lo) < 0 { return false }
        if let hi = band.maxFirmware, compare(hi, version) < 0 { return false }
        return true
    }

    public static func model(_ id: String) -> Model? {
        models.first(where: { $0.id == id })
    }

    /// Возможности модели на конкретной прошивке. Одна полоса — берём её без
    /// разбора версии, как делает донор; иначе ищем подходящую. Пустой словарь
    /// значит «версия не попала ни в одну полосу» — не «возможностей нет».
    public static func flags(model id: String, firmware: String) -> [Flag: Int] {
        guard let m = model(id) else { return [:] }
        if m.bands.count == 1 { return m.bands[0].flags }
        return m.bands.first(where: { inBand(firmware, $0) })?.flags ?? [:]
    }

    /// Раскладка жестов модели на конкретной прошивке. Полоса выбирается тем
    /// же способом, что и флаги, — иначе B157 на старой прошивке получит
    /// шумоподавление, которого у него на ней нет.
    public static func gestures(model id: String, firmware: String) -> [GestureSlot] {
        guard let m = model(id) else { return [] }
        if m.bands.count == 1 { return m.bands[0].gestures }
        return m.bands.first(where: { inBand(firmware, $0) })?.gestures ?? []
    }

    /// Ступени силы шумоподавления, доступные модели.
    ///
    /// Маска `ancLevel` — не догадка: биты объявлены константами в
    /// `device_common.js` и там же стоят гейтами интерфейса. `0x04`
    /// открывает силу вообще (High и Low), `0x02` добавляет Mid, `0x08`
    /// Adaptive. Порядок здесь — по нарастанию подавления, Adaptive
    /// последним: он не ступень, а «выбирай сам».
    ///
    /// Пустой список значит «селектора силы нет», а не «шумоподавления нет»:
    /// у B174 и B189 ключа `ancLevel` в конфиге нет вовсе, а режим они
    /// читают. Донор ведёт себя так же — `undefined & маска` даёт ноль.
    public static func noiseStrengths(model id: String, firmware: String) -> [NothingProtocol.NoiseStrength] {
        let mask = flags(model: id, firmware: firmware)[.ancLevel] ?? 0
        guard mask & 0x04 != 0 else { return [] }
        var out: [NothingProtocol.NoiseStrength] = [.low]
        if mask & 0x02 != 0 { out.append(.mid) }
        out.append(.high)
        if mask & 0x08 != 0 { out.append(.adaptive) }
        return out
    }

    /// Есть ли у модели прозрачность. Тот же бит, тот же источник.
    public static func hasTransparency(model id: String, firmware: String) -> Bool {
        (flags(model: id, firmware: firmware)[.ancLevel] ?? 0) & 0x10 != 0
    }

    /// Имеет ли смысл слать команду этому устройству.
    public static func supports(_ op: Op, model id: String, firmware: String) -> Bool {
        switch op.requires {
        case .always:                 return true
        case .flag(let f):            return (flags(model: id, firmware: firmware)[f] ?? 0) != 0
        case .onlyModels(let list):   return list.contains(id)
        case .exceptModels(let list): return !list.contains(id)
        }
    }

    /// Команды, доступные устройству.
    public static func operations(model id: String, firmware: String) -> [Op] {
        operations.filter { supports($0, model: id, firmware: firmware) }
    }
}
