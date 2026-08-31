import Foundation

func trace(_ s: String) {}          // заглушка: в приложении она в main.swift

// Проверка нормализации ссылок с сайта. Главное здесь — обход, которым
// пробивался прежний вариант с заменой подстроки "../" на пустую:
// строка "....//x" после такой замены превращалась в "../x".
@main
struct NormalizeTest {
    static let cases: [(String, String?)] = [
        ("....//x.js", nil),
        ("....//....//....//LaunchAgents/x.plist", nil),
        ("..././x.js", nil),
        ("../js/control.js", "js/control.js"),          // штатная ссылка со страницы устройства
        ("../../../../etc/passwd", "etc/passwd"),       // выше корня копии не поднимаемся
        ("js/../assets/a.webp", "assets/a.webp"),
        ("~/secret", nil),
        ("/js/ear_config_file.json", "js/ear_config_file.json"),
        ("assets/b170_black_left.webp", "assets/b170_black_left.webp"),
    ]

    static func main() {
        var bad = 0
        for (input, expected) in cases {
            let got = SiteUpdater.normalizeRef(input)
            let ok = got == expected
            if !ok { bad += 1 }
            let label = input.padding(toLength: 42, withPad: " ", startingAt: 0)
            print("\(ok ? "ок   " : "ПЛОХО") \(label) → \(got ?? "отброшено")")
        }
        print(bad == 0 ? "\nвсе проверки прошли" : "\nпровалено: \(bad)")
        exit(bad == 0 ? 0 : 1)
    }
}
