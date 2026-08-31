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

    /// Откуда взято знание о команде. Физически доступна одна модель, B170,
    /// поэтому провод подтверждает только её; всё прочее выведено чтением
    /// чужого кода и может оказаться неверным.
    public enum Evidence: String {
        /// Спрошено у B170 и получен ответ.
        case wire
        /// Спрошено у B170 и ответа не было. Неподдерживаемое устройство
        /// молчит, а не отвечает отказом, — это сильнее догадки по конфигу.
        case silent
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
        .init(code: 0xF003, name: "gestures", role: .write, requires: .always, evidence: .derived),
        .init(code: 0xF004, name: "inEar", role: .write, requires: .exceptModels(["B174", "B175", "B185", "B186", "B189"]), evidence: .derived),
        .init(code: 0xF00A, name: "utcTime", role: .write, requires: .exceptModels(["B181"]), evidence: .wire),
        .init(code: 0xF00D, name: "ledCaseColor", role: .write, requires: .onlyModels(["B181"]), evidence: .derived),
        .init(code: 0xF00F, name: "anc", role: .write, requires: .always, evidence: .derived),
        .init(code: 0xF010, name: "eq", role: .write, requires: .exceptModels(["B168", "B172", "B175", "B179", "B184", "B185", "B189"]), evidence: .derived),
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
        .init(code: 0xF050, name: "advancedEQValue", role: .write, requires: .always, evidence: .derived),
        .init(code: 0xF051, name: "enhancedBass", role: .write, requires: .onlyModels(["B162", "B164", "B168", "B170", "B171", "B172", "B173", "B179", "B184", "B186", "B189"]), evidence: .derived),
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

    /// Полоса прошивок: набор возможностей действует не для модели целиком,
    /// а для диапазона версий. У B170, например, персональный звук появился
    /// только с *.*.1.75 — на более старой прошивке команды просто нет.
    public struct Band {
        public let minFirmware: String?
        public let maxFirmware: String?
        public let flags: [Flag: Int]
    }

    public struct Model {
        public let id: String
        public let bands: [Band]
    }

    /// 23 моделей.
    public static let models: [Model] = [
        .init(id: "B181", bands: [
            .init(minFirmware: nil, maxFirmware: "*.*.1.74", flags: [.ancLevel: 53, .buttonPosition: 4, .dualConnection: 0, .eq: 15, .findDevice: 1, .lowLagMode: 0, .serialNumber: 0, .utcTime: 0]),
            .init(minFirmware: "*.*.1.75", maxFirmware: "*.*.1.85", flags: [.ancLevel: 53, .buttonPosition: 4, .dualConnection: 0, .eq: 15, .findDevice: 1, .serialNumber: 0, .utcTime: 0]),
            .init(minFirmware: "*.*.1.86", maxFirmware: nil, flags: [.ancLevel: 53, .buttonPosition: 4, .dualConnection: 0, .eq: 15, .findDevice: 1, .serialNumber: 0, .utcTime: 0]),
        ]),
        .init(id: "B157", bands: [
            .init(minFirmware: "*.*.2.0", maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -11, .ancLevel: 33, .buttonPosition: 4, .dualConnection: 0, .noiseReduction: 1]),
            .init(minFirmware: nil, maxFirmware: "*.*.1.79", flags: [.ancLevel: 0, .buttonPosition: 4, .dualConnection: 0, .noiseReduction: 2]),
            .init(minFirmware: "*.*.1.80", maxFirmware: "*.*.1.999", flags: [.advancedEq: 1, .advancedEqTotalGain: -11, .ancLevel: 0, .buttonPosition: 4, .dualConnection: 0, .noiseReduction: 2]),
        ]),
        .init(id: "B155", bands: [
            .init(minFirmware: nil, maxFirmware: "*.*.1.94", flags: [.advancedEq: 0, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 4, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 2, .mimi: 1, .personalizedAnc: 1]),
            .init(minFirmware: "*.*.1.95", maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 4, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 2, .mimi: 1, .personalizedAnc: 1]),
        ]),
        .init(id: "B162", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 4, .ultraBass: 1]),
        ]),
        .init(id: "B171", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 4, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 7, .mimi: 1, .ultraBass: 1]),
        ]),
        .init(id: "B163", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 55, .buttonPosition: 2, .dualConnection: 0]),
        ]),
        .init(id: "B164", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 3, .deviceType: 6, .dualConnection: 1, .earDetection: 0, .spatialAudio: 6, .ultraBass: 1]),
        ]),
        .init(id: "B168", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 49, .buttonPosition: 4, .dualConnection: 1, .eq: 0, .ultraBass: 1]),
        ]),
        .init(id: "B172", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 0, .highQualityAudio: 4, .smartKnob: 1, .spatialAudio: 6, .ultraBass: 1]),
        ]),
        .init(id: "B174", bands: [
            .init(minFirmware: nil, maxFirmware: "1.0.1.26", flags: [.advancedEq: 1, .buttonPosition: 2, .dualConnection: 1, .earDetection: 0, .eq: 31, .ultraBass: 0]),
            .init(minFirmware: "1.0.1.27", maxFirmware: "1.0.1.27", flags: [.adapterVolume: 1, .advancedEq: 1, .buttonPosition: 2, .dualConnection: 1, .earDetection: 0, .eq: 31, .ultraBass: 0]),
            .init(minFirmware: "1.0.1.28", maxFirmware: nil, flags: [.advancedEq: 1, .buttonPosition: 2, .dualConnection: 1, .earDetection: 0, .eq: 31, .ultraBass: 0]),
        ]),
        .init(id: "B170", bands: [
            .init(minFirmware: nil, maxFirmware: "*.*.1.74", flags: [.advancedEq: 1, .ancLevel: 63, .deviceType: 6, .dualConnection: 1, .earDetection: 1, .eq: 31, .findDevice: 1, .highQualityAudio: 4, .magicButton: 1, .mutuallyExclusive: 1, .spatialAudio: 7, .ultraBass: 1]),
            .init(minFirmware: "*.*.1.75", maxFirmware: nil, flags: [.advancedEq: 1, .ancLevel: 63, .audiodo: 1, .deviceType: 6, .dualConnection: 1, .earDetection: 1, .eq: 31, .findDevice: 1, .highQualityAudio: 4, .magicButton: 1, .mutuallyExclusive: 1, .spatialAudio: 7, .ultraBass: 1]),
        ]),
        .init(id: "B175", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .audiodo: 1, .deviceType: 6, .dualConnection: 1, .earDetection: 0, .findDevice: 1, .highQualityAudio: 4, .spatialAudio: 28, .ultraBass: 0]),
        ]),
        .init(id: "B185", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 49, .buttonPosition: 4, .dualConnection: 1, .earDetection: 0, .eq: 0, .ultraBass: 1]),
        ]),
        .init(id: "B179", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .spatialAudio: 6, .ultraBass: 1]),
        ]),
        .init(id: "B184", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .audiodo: 1, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .highQualityAudio: 4, .spatialAudio: 6, .ultraBass: 1]),
        ]),
        .init(id: "B173", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .audiodo: 1, .buttonPosition: 1, .callTransparency: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .superMic: 1, .ultraBass: 1, .walkieTalkieMode: 1]),
        ]),
        .init(id: "B183", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .ultraBass: 1]),
        ]),
        .init(id: "B187", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.ancLevel: 63, .buttonPosition: 0, .dualConnection: 1, .earTipFitTest: 1, .eq: 0, .highQualityAudio: 4, .smartKnob: 1, .spatialAudio: 6, .ultraBass: 1]),
        ]),
        .init(id: "B186", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .ancLevel: 63, .audiodo: 0, .deviceType: 6, .dualConnection: 1, .earDetection: 0, .eq: 31, .findDevice: 1, .highQualityAudio: 4, .magicButton: 1, .mutuallyExclusive: 0, .spatialAudio: 28, .ultraBass: 1, .ultraBassType: 3]),
        ]),
        .init(id: "B198", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .ancLevel: 63, .audiodo: 0, .deviceType: 6, .dualConnection: 1, .earDetection: 0, .eq: 31, .findDevice: 1, .highQualityAudio: 4, .magicButton: 1, .mutuallyExclusive: 0, .spatialAudio: 28, .ultraBass: 1, .ultraBassType: 3]),
        ]),
        .init(id: "B201", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .audiodo: 1, .buttonPosition: 1, .callTransparency: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .superMic: 1, .ultraBass: 1, .walkieTalkieMode: 1]),
        ]),
        .init(id: "B190", bands: [
            .init(minFirmware: nil, maxFirmware: "1.0.1.36", flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .ultraBass: 0, .walkieTalkieMode: 0]),
            .init(minFirmware: "1.0.1.37", maxFirmware: "1.0.1.60", flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .ultraBass: 0, .walkieTalkieMode: 0]),
            .init(minFirmware: "1.0.1.61", maxFirmware: nil, flags: [.advancedEq: 1, .advancedEqTotalGain: -6, .ancLevel: 63, .buttonPosition: 1, .dualConnection: 1, .earTipFitTest: 1, .eq: 31, .highQualityAudio: 4, .spatialAudio: 6, .ultraBass: 0, .walkieTalkieMode: 0]),
        ]),
        .init(id: "B189", bands: [
            .init(minFirmware: nil, maxFirmware: nil, flags: [.advancedEq: 0, .buttonPosition: 2, .dualConnection: 1, .earDetection: 0, .highQualityAudio: 4, .longPowerMode: 1, .spatialAudio: 6, .supportLeakageProtection: 1, .ultraBass: 1, .ultraBassType: 3]),
        ]),
    ]

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
