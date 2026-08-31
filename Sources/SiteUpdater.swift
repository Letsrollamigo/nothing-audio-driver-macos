import Foundation

// Хранилище копий сайта: вшитая в бандл и скачанные в Application Support.
// Активной считается самая свежая скачанная, иначе вшитая.
enum SiteStore {
    static let liveBase = URL(string: "https://earweb.bttl.xyz/")!
    /// По этим файлам определяем, изменился ли сайт: два самых «живых» скрипта и конфиг.
    static let probeFiles = ["index.html", "js/bluetooth_socket.js", "js/ear_config_file.json"]

    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ear-local", isDirectory: true)
    }
    static var bundledSite: URL { Bundle.main.resourceURL!.appendingPathComponent("site", isDirectory: true) }

    /// Скачанные копии, новейшая первой. Имя каталога — метка времени сборки копии.
    static func downloadedSites() -> [URL] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.lastPathComponent.hasPrefix("site-") && fm.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Копия сайта, с которой работаем. Вшитой может не быть вовсе — репозиторий
    /// не распространяет чужие файлы, и тогда первая копия скачивается при старте.
    static func activeSite() -> URL? {
        if let downloaded = downloadedSites().first { return downloaded }
        let bundled = bundledSite
        return FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.html").path) ? bundled : nil
    }

    /// Last-Modified ключевых файлов на момент, когда копия была скачана.
    static func storedDates(in site: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: site.appendingPathComponent("meta.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return obj
    }

    static func activeLabel() -> String {
        guard let dir = downloadedSites().first else {
            return activeSite() == nil ? "копии сайта нет" : "вшитая копия"
        }
        return "копия от " + dir.lastPathComponent.replacingOccurrences(of: "site-", with: "")
    }

    /// Оставляем только активную копию — Application Support не должен расти.
    @discardableResult
    static func prune(keeping explicitKeep: String? = nil) -> Int {
        let fm = FileManager.default
        var removed = 0
        // Что оставить, решает вызывающий: полагаться на сортировку имён нельзя.
        let keep = explicitKeep ?? downloadedSites().first?.lastPathComponent
        let items = (try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)) ?? []
        for item in items {
            let name = item.lastPathComponent
            // Чистим и старые копии, и брошенные каталоги незавершённых загрузок.
            let isOldSite = name.hasPrefix("site-") && name != keep
            let isLeftoverTmp = name.hasPrefix("tmp-")
            guard isOldSite || isLeftoverTmp else { continue }
            if (try? fm.removeItem(at: item)) != nil { removed += 1 }
        }
        return removed
    }
}

enum SiteUpdater {
    /// Есть ли на сайте что-то новее активной копии. Сверяем размеры через HEAD:
    /// дёшево, без скачивания и без отдельного файла-отпечатка при сборке.
    static func checkForUpdate(completion: @escaping (Bool) -> Void) {
        guard let site = SiteStore.activeSite() else { completion(true); return }   // копии нет — качаем
        let knownDates = SiteStore.storedDates(in: site)
        let group = DispatchGroup()
        var differs = false
        var reachable = false

        for rel in SiteStore.probeFiles {
            guard let localSize = try? FileManager.default
                    .attributesOfItem(atPath: site.appendingPathComponent(rel).path)[.size] as? Int else { continue }
            var req = URLRequest(url: SiteStore.liveBase.appendingPathComponent(rel))
            req.httpMethod = "HEAD"
            req.timeoutInterval = 8
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            group.enter()
            URLSession.shared.dataTask(with: req) { _, response, _ in
                defer { group.leave() }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
                reachable = true
                // Content-Length приходит не всегда (HTML отдаётся сжатым), поэтому
                // основной признак — Last-Modified из meta.json нашей копии,
                // а размер остаётся запасным.
                if let knownDate = knownDates[rel], let remoteDate = http.value(forHTTPHeaderField: "Last-Modified") {
                    if remoteDate != knownDate {
                        trace("обновление: \(rel) на сайте от \(remoteDate), у нас от \(knownDate)")
                        differs = true
                    }
                    return
                }
                let remoteSize = Int(http.value(forHTTPHeaderField: "Content-Length") ?? "") ?? -1
                if remoteSize > 0, remoteSize != localSize {
                    trace("обновление: \(rel) на сайте \(remoteSize) б против \(localSize) б локально")
                    differs = true
                }
            }.resume()
        }
        group.notify(queue: .main) {
            if !reachable { trace("обновление: сайт недоступен, работаем на текущей копии") }
            completion(reachable && differs)
        }
    }

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    private static let refPattern = try! NSRegularExpression(
        pattern: #"(?:src|href)\s*=\s*["']([^"']+)["']|url\(\s*["']?([^"')]+)["']?\s*\)|["']([\w./-]+\.(?:js|json|css|svg|webp|png|jpg|otf|ttf|woff2?))["']"#)
    private static let cfBeacon = try! NSRegularExpression(
        pattern: #"<script>\(function\(\)\{.*?__CF\$cv\$params.*?</script>|<script[^>]*cloudflareinsights[^>]*>\s*</script>"#,
        options: [.dotMatchesLineSeparators])

    private static var downloading = false

    /// Полное зеркалирование сайта во временный каталог, затем атомарная подмена.
    /// Текстовые файлы обходим последовательно (из них извлекаются ссылки),
    /// а бинарные ассеты качаем пачкой параллельно — иначе 344 файла тянутся минутами.
    static func download(completion: @escaping (Bool, String) -> Void) {
        guard !downloading else { completion(false, "скачивание уже идёт"); return }
        downloading = true
        DispatchQueue.global(qos: .utility).async {
            defer { downloading = false }
            let fm = FileManager.default
            let stamp = stampNow()
            let tmp = SiteStore.appSupport.appendingPathComponent("tmp-\(stamp)", isDirectory: true)
            func fail(_ why: String) {
                try? fm.removeItem(at: tmp)
                DispatchQueue.main.async { completion(false, why) }
            }
            do { try fm.createDirectory(at: tmp, withIntermediateDirectories: true) }
            catch { fail("не создать каталог: \(error.localizedDescription)"); return }

            let tmpRoot = tmp.standardizedFileURL.path
            func save(_ rel: String, _ data: Data) -> Bool {
                var localRel = rel
                if (rel as NSString).pathExtension.isEmpty { localRel += ".html" }   // /MainControl_x → .html
                let dest = tmp.appendingPathComponent(localRel).standardizedFileURL
                // Последний рубеж: что бы ни пришло с сайта, писать только внутрь
                // каталога загрузки. Сайт может отдать ссылку, уводящую наружу.
                guard dest.path.hasPrefix(tmpRoot + "/") else {
                    trace("обновление: путь ведёт наружу, пропускаю — \(rel)")
                    return false
                }
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                return (try? data.write(to: dest)) != nil
            }

            var queue: [String] = ["index.html", "global.css", "tailwind.css", "manifest.json", "robots.txt"]
            guard let nav = fetch("js/nothing_connected.js"), let navText = String(data: nav, encoding: .utf8) else {
                fail("сайт недоступен"); return
            }
            let pageRe = try! NSRegularExpression(pattern: #"location\.href\s*=\s*"(MainControl_\w+)""#)
            for m in pageRe.matches(in: navText, range: NSRange(navText.startIndex..., in: navText)) {
                if let r = Range(m.range(at: 1), in: navText) { queue.append(String(navText[r])) }
            }
            trace("обновление: страниц устройств \(queue.count - 5)")

            var seen = Set(queue)
            var assets = [String]()
            var saved = 0, failed = 0

            // Фаза 1 — текст: html/css/js/json, из них же вытаскиваем ссылки.
            while let rel = queue.first {
                queue.removeFirst()
                guard let data = fetch(rel) else { failed += 1; continue }
                var payload = data
                var ext = (rel as NSString).pathExtension.lowercased()
                if ext.isEmpty { ext = "html" }
                if ext == "html", var text = String(data: data, encoding: .utf8) {
                    text = cfBeacon.stringByReplacingMatches(
                        in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
                    payload = Data(text.utf8)
                }
                if save(rel, payload) { saved += 1 } else { failed += 1; continue }

                guard ["html", "css", "js"].contains(ext), let text = String(data: payload, encoding: .utf8) else { continue }
                for m in refPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    var ref: String?
                    for i in 1...3 where m.range(at: i).location != NSNotFound {
                        if let r = Range(m.range(at: i), in: text) { ref = String(text[r]); break }
                    }
                    guard var candidate = ref, !candidate.hasPrefix("http"), !candidate.hasPrefix("//"),
                          !candidate.hasPrefix("data:"), !candidate.hasPrefix("mailto:"), !candidate.hasPrefix("#")
                    else { continue }
                    candidate = candidate.components(separatedBy: "?")[0].components(separatedBy: "#")[0]
                    guard let normalized = normalizeRef(candidate),
                          !normalized.contains("cdn-cgi"), !seen.contains(normalized) else { continue }
                    seen.insert(normalized)
                    let e = (normalized as NSString).pathExtension.lowercased()
                    if ["html", "css", "js", "json", ""].contains(e) { queue.append(normalized) } else { assets.append(normalized) }
                }
            }
            trace("обновление: текстовых файлов \(saved), в очереди ассетов \(assets.count)")

            // Фаза 2 — ассеты. Ограничиваем число ЗАПРОСОВ в полёте, а не число
            // занятых потоков: раньше каждый запрос держал поток на семафоре,
            // GCD душил пул, и загрузка занимала минуты с потерями.
            let lock = NSLock()
            let inFlight = DispatchSemaphore(value: 12)
            let group = DispatchGroup()
            var done = 0
            var lost = [String]()
            for rel in assets {
                inFlight.wait()
                group.enter()
                fetchAsync(rel) { data in
                    lock.lock()
                    if let data, save(rel, data) { saved += 1 } else { failed += 1; lost.append(rel) }
                    done += 1
                    if done % 100 == 0 { trace("обновление: ассетов \(done)/\(assets.count)") }
                    lock.unlock()
                    inFlight.signal()
                    group.leave()
                }
            }
            group.wait()
            if !lost.isEmpty { trace("обновление: не скачалось — \(lost.prefix(20).joined(separator: ", "))") }

            // Меняем копию только если новая не беднее текущей: иначе одна неудачная
            // сессия связи подменила бы полный слепок дырявым.
            let currentCount = (SiteStore.activeSite().flatMap { try? fm.subpathsOfDirectory(atPath: $0.path) })?
                .filter { !$0.hasSuffix(".DS_Store") }.count ?? 0
            let minimum = max(30, Int(Double(currentCount) * 0.98))
            guard fm.fileExists(atPath: tmp.appendingPathComponent("index.html").path) else {
                fail("в копии нет index.html, не меняю"); return
            }
            guard saved >= minimum else {
                fail("скачано \(saved) файлов при пороге \(minimum) (сейчас \(currentCount)) — копию не меняю"); return
            }
            // Метки времени ключевых файлов — по ним следующая проверка поймёт,
            // что сайт изменился, даже если длина осталась прежней.
            var dates = [String: String]()
            let dgroup = DispatchGroup()
            let dlock = NSLock()
            for rel in SiteStore.probeFiles {
                var head = URLRequest(url: SiteStore.liveBase.appendingPathComponent(rel))
                head.httpMethod = "HEAD"
                head.timeoutInterval = 10
                head.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                dgroup.enter()
                URLSession.shared.dataTask(with: head) { _, response, _ in
                    defer { dgroup.leave() }
                    guard let http = response as? HTTPURLResponse,
                          let lm = http.value(forHTTPHeaderField: "Last-Modified") else { return }
                    dlock.lock(); dates[rel] = lm; dlock.unlock()
                }.resume()
            }
            _ = dgroup.wait(timeout: .now() + 15)
            if let metaData = try? JSONSerialization.data(withJSONObject: dates) {
                try? metaData.write(to: tmp.appendingPathComponent("meta.json"))
                trace("обновление: сохранены метки времени для \(dates.count) файлов")
            }

            let final = SiteStore.appSupport.appendingPathComponent("site-\(stamp)", isDirectory: true)
            do { try fm.moveItem(at: tmp, to: final) }
            catch { fail("не переместить копию: \(error.localizedDescription)"); return }
            let pruned = SiteStore.prune(keeping: final.lastPathComponent)
            DispatchQueue.main.async {
                completion(true, "обновлено: файлов \(saved), не скачалось \(failed), убрано старых копий \(pruned)")
            }
        }
    }

    /// Приводит ссылку с сайта к пути внутри копии. Страницы лежат в корне и
    /// ссылаются как ../js/… — лишние «вверх» схлопываются к корню, но любой
    /// выход за пределы отбрасывается. Простая замена "../" на "" тут не годится:
    /// строка "....//x" после неё превращается в "../x" и уводит наружу.
    static func normalizeRef(_ raw: String) -> String? {
        var stack = [String]()
        for part in raw.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !stack.isEmpty { stack.removeLast() }      // выше корня не поднимаемся
            default:
                let s = String(part)
                guard s != "~", !s.hasPrefix("."), !s.contains("\\") else { return nil }
                stack.append(s)
            }
        }
        let result = stack.joined(separator: "/")
        return result.isEmpty ? nil : result
    }

    /// Асинхронная загрузка с повторами: одиночные срывы под нагрузкой — норма,
    /// без повторов они выедали десятки картинок из копии.
    private static func fetchAsync(_ rel: String, attempt: Int = 1, completion: @escaping (Data?) -> Void) {
        var req = URLRequest(url: SiteStore.liveBase.appendingPathComponent(rel))
        req.timeoutInterval = 20
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")   // без этого Cloudflare отдаёт 403
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200, let data { completion(data); return }
            if code == 404 { completion(nil); return }              // повторять нечего
            guard attempt < 3 else { completion(nil); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(attempt) * 0.7) {
                fetchAsync(rel, attempt: attempt + 1, completion: completion)
            }
        }.resume()
    }

    /// Синхронная обёртка для последовательной текстовой фазы.
    private static func fetch(_ rel: String) -> Data? {
        var result: Data?
        let sem = DispatchSemaphore(value: 0)
        fetchAsync(rel) { result = $0; sem.signal() }
        _ = sem.wait(timeout: .now() + 70)
        return result
    }

    private static func stampNow() -> String {
        let f = DateFormatter()
        // Без POSIX-локали и григорианского календаря японская/буддийская локаль
        // даёт год вида 0008 — новая копия сортируется НИЖЕ старой, и чистка
        // сносит именно ту, которую только что установили.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: Date())
    }
}
