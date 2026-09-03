import Foundation

// Локализация интерфейса.
//
// Сделана таблицей в коде, а не каталогами `.lproj`, по двум причинам, и обе
// внешние: язык должен переключаться на лету, а `NSLocalizedString` берёт его
// при запуске и требует перезапуска; и в `Contents/Resources` нельзя ничего,
// кроме значка и шима, — на этом намеренно падает CI, и обходить проверку
// ради строк нельзя.
//
// Ключ — английская строка. Тогда таблица не расходится с кодом молча:
// пропущенный перевод отдаёт английский, а не «MISSING_KEY», и переименование
// строки в коде видно сразу.

enum Language: String, CaseIterable, Identifiable {
    case system, english, russian

    var id: String { rawValue }

    /// Подпись самого языка не переводится: список языков в любом интерфейсе
    /// пишется на этих языках, иначе своё название не найти.
    var title: String {
        switch self {
        case .system:  return Strings.shared.resolved == .russian ? "Системный" : "System"
        case .english: return "English"
        case .russian: return "Русский"
        }
    }
}

final class Strings: ObservableObject {
    static let shared = Strings()

    private static let key = "interface-language"

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        language = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(Language.init(rawValue:)) ?? .system
    }

    /// Язык, на котором рисуем на самом деле: «системный» разворачивается
    /// в конкретный. Всё, что не русский, — английский: третьего перевода нет,
    /// и делать вид, что есть, незачем.
    var resolved: Language {
        guard language == .system else { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ru") ? .russian : .english
    }

    func callAsFunction(_ english: String) -> String {
        guard resolved == .russian else { return english }
        return Strings.russian[english] ?? english
    }
}

/// Короткое имя для места, где строка попадает на экран.
func t(_ english: String) -> String { Strings.shared(english) }

extension Strings {
    static let russian: [String: String] = [
        // Стартовый экран
        "Connect your headphones": "Подключите наушники",
        "Looking for your headphones…": "Ищу наушники…",
        "Couldn’t connect": "Не удалось подключиться",
        "The app talks to Nothing and CMF headphones over Bluetooth.":
            "Приложение общается с наушниками Nothing и CMF по Bluetooth.",
        "Opening the identification and control channels.":
            "Открываю каналы опознания и управления.",
        "Connect": "Подключить",
        "Connecting…": "Подключаюсь…",
        "If nothing happens, check that:": "Если ничего не происходит, проверьте:",
        "the headphones are switched on and out of the case":
            "наушники включены и вынуты из кейса",
        "they are paired in System Settings › Bluetooth":
            "они сопряжены в «Системных настройках» › Bluetooth",
        "no other app is holding the connection":
            "соединение не занято другой программой",

        // Состояние связи
        "Not connected": "Нет подключения",
        "Connected": "Подключено",
        "connection lost": "связь потеряна",
        "no access to Bluetooth": "Нет доступа к Bluetooth",
        "the device with this service was not found — is it on and paired?":
            "Устройство с нужным сервисом не найдено — включено ли оно и сопряжено?",
        "the identification channel is unavailable — reconnect the headphones and try again":
            "Канал опознания недоступен — переподключите наушники и попробуйте снова",
        "the connection is busy or the device is not responding":
            "соединение занято или устройство не отвечает",
        "Reconnect": "Переподключить",
        "Nothing device": "Устройство Nothing",

        // Заряд
        "Battery": "Заряд",
        "No reading yet": "Показаний пока нет",
        "Left": "Левый",
        "Right": "Правый",
        "Case": "Кейс",
        "Headphones": "Наушники",

        // Шумоподавление
        "Listening mode": "Режим прослушивания",
        "Mode": "Режим",
        "Noise cancellation": "Шумоподавление",
        "Transparency": "Прозрачность",
        "Off": "Выключено",
        "Strength": "Уровень",
        // Значения согласованы с подписью «Уровень»: прилагательные мужского
        // рода, и шкала та же, что в протоколе, — низкий/средний/высокий.
        "Low": "Низкий",
        "Mid": "Средний",
        "High": "Высокий",
        "Adaptive": "Адаптивный",
        "Noise cancellation at full strength.": "Шумоподавление на максимуме.",
        "Noise cancellation, medium strength.": "Шумоподавление вполсилы.",
        "Noise cancellation, light strength.": "Слабое шумоподавление.",
        "Strength follows the noise around you.": "Уровень подстраивается под шум вокруг.",
        "No processing — passive isolation only.":
            "Без обработки — только пассивная изоляция.",
        "Outside sound is passed through.": "Внешние звуки пропускаются наружу.",

        // Эквалайзер
        "Equaliser": "Эквалайзер",
        "Preset": "Пресет",
        "Balanced": "Сбалансированный",
        "Voice": "Голос",
        "More Treble": "Больше высоких",
        "More Bass": "Больше баса",
        "Custom": "Свой",
        "Sound profile": "Профиль звучания",
        "Profile": "Профиль",
        "Rock": "Рок",
        "Electronic": "Электронная",
        "Pop": "Поп",
        "Vocals": "Вокал",
        "Classical": "Классика",
        "Advanced EQ is active on the headphones — picking a preset switches it off.":
            "На наушниках включён расширенный эквалайзер — выбор пресета его выключит.",
        "Applying…": "Применяю…",
        "· applying…": "· применяю…",

        // Расширенный эквалайзер.
        // «Q» не переводим: «добротность» — верный термин теории фильтров,
        // но в аудио-интерфейсах ожидают именно букву, и она короче.
        "Advanced equaliser": "Расширенный эквалайзер",
        "Fine tune": "Точная настройка",
        "Frequency": "Частота",
        "Q factor": "Q",
        "Moving a slider switches the advanced equaliser on and replaces the preset.":
            "Движение ползунка включает расширенный эквалайзер и заменяет пресет.",

        // Бас
        "Bass": "Бас",
        "Bass enhance": "Усиление баса",
        "Level": "Уровень",
        "Not available while spatial audio is on.":
            "Недоступно, пока включён пространственный звук.",

        // Жесты: органы и сами жесты
        "Controls": "Управление",
        "Roller": "Колесо",
        "Button": "Кнопка",
        "Slider": "Ползунок",
        "Dial": "Циферблат",
        "Press": "Нажатие",
        "Double press": "Двойное нажатие",
        "Triple press": "Тройное нажатие",
        "Slide": "Свайп",
        "Hold": "Удержание",
        "Double press and hold": "Двойное нажатие с удержанием",
        "Rotate": "Поворот",
        "Pinch both": "Сжатие обоих",

        // Жесты: действия
        "No action": "Ничего",
        "Play / pause": "Плей / пауза",
        "Answer call": "Ответить на звонок",
        "Previous track": "Предыдущий трек",
        "Next track": "Следующий трек",
        "Noise control": "Шумоподавление",
        "Voice assistant": "Голосовой помощник",
        "Low lag mode": "Режим низкой задержки",
        "Volume up": "Громче",
        "Volume down": "Тише",
        "Volume": "Громкость",
        "Camera shutter": "Спуск затвора",
        "Answer and mute": "Ответить и заглушить",
        "Hang up": "Положить трубку",
        "Spatial audio": "Пространственный звук",
        "Mic mute": "Выключить микрофон",
        "News reporter": "Новости",
        "Channel hop": "Переключение канала",
        "Essential Space": "Essential Space",
        "EQ preset": "Пресет эквалайзера",
        "Ultra bass": "Ультрабас",
        "Treble enhance": "Усиление высоких",
        "Recording": "Запись",

        // Язык и тема
        "Language": "Язык",
        "System": "Системная",
        "Light": "Светлая",
        "Dark": "Тёмная",

        // Пространственный звук и поведение устройства
        "Head tracking": "Следит за головой",
        "Fixed": "Фиксированный",
        "Concert": "Концерт",
        "Theatre": "Театр",
        "Game": "Игра",
        "Not available while bass enhance or the advanced equaliser is on.":
            "Недоступно, пока включено усиление баса или расширенный эквалайзер.",
        "Device": "Устройство",
        "Pause when removed": "Пауза при снятии",
        "Low latency mode": "Режим низкой задержки",
        "Codec": "Кодек",
        "Personal sound": "Персональный звук",
        "Sound": "Звук",
        "Dual connection": "Подключение к двум устройствам",
        "Switching the mode reboots the headphones.":
            "Переключение режима перезагружает наушники.",
        "This Mac": "Этот компьютер",
        "Unnamed device": "Устройство без имени",
        "Disconnect": "Отключить",
        "Find device": "Поиск устройства",
        "Find headphones": "Найти наушники",
        "Open window": "Открыть окно",
        "Looking for headphones…": "Ищу наушники…",
        "Quit": "Выйти",
        "Play sound": "Позвонить",
        "Stop": "Остановить",
        "Switching the codec reboots the headphones.":
            "Смена кодека перезагружает наушники.",

        // Единицы
        "Hz": "Гц",
        "kHz": "кГц",
        "dB": "дБ",
    ]
}
