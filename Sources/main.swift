import AppKit
import WebKit
import IOBluetooth

let SPP_UUID = "aeac4a03-dff5-498f-843a-34487cf133eb"
let FASTPAIR_UUID = "df21fe2c-2515-4fdb-8886-f12c4d67927c"

let logURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/ear-local.log")
func trace(_ s: String) {
    let line = "\(Date().formatted(date: .omitted, time: .standard))  \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}
let SCHEME = "earlocal"

func hexString(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

func hexBytes(_ hex: String) -> [UInt8] {
    stride(from: 0, to: hex.count, by: 2).map { i -> UInt8 in
        let idx = hex.index(hex.startIndex, offsetBy: i)
        return UInt8(hex[idx...hex.index(idx, offsetBy: 1)], radix: 16) ?? 0
    }
}

/// Строка, пригодная для вставки в JS. Нужна только оболочке: мост про веб
/// не знает и отдаёт причину обычной строкой.
func jsString(_ s: String) -> String {
    let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    return "'\(escaped)'"
}

// MARK: - раздача сайта из бандла

final class SiteHandler: NSObject, WKURLSchemeHandler {
    private let root: () -> URL?
    init(root: @escaping () -> URL?) { self.root = root }

    private static let mime: [String: String] = [
        "html": "text/html", "js": "text/javascript", "css": "text/css",
        "json": "application/json", "svg": "image/svg+xml", "webp": "image/webp",
        "png": "image/png", "jpg": "image/jpeg", "otf": "font/otf", "ttf": "font/ttf",
        "txt": "text/plain",
    ]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        // url.path уже раскодирован, поэтому %2f превращается в разделитель:
        // без нормализации страница может прочитать любой файл пользователя.
        var rel = SiteUpdater.normalizeRef(url.path) ?? "index.html"
        if rel.isEmpty { rel = "index.html" }
        // тот же роутинг, что у server.py: /MainControl_x → MainControl_x.html
        if (rel as NSString).pathExtension.isEmpty { rel += ".html" }
        guard let base = root()?.standardizedFileURL else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorResourceUnavailable))
            return
        }
        let file = base.appendingPathComponent(rel).standardizedFileURL
        guard file.path.hasPrefix(base.path + "/") else {
            trace("сайт: путь ведёт наружу, отказ — \(url.path)")
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNoPermissionsToReadFile))
            return
        }

        guard let data = try? Data(contentsOf: file) else {
            trace("сайт: НЕТ ФАЙЛА \(rel)")
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist,
                                          userInfo: [NSLocalizedDescriptionKey: "нет файла: \(rel)"]))
            return
        }
        if file.pathExtension.lowercased() == "json" { trace("сайт: отдан \(rel) (\(data.count) б)") }
        let type = Self.mime[file.pathExtension.lowercased()] ?? "application/octet-stream"
        // Именно HTTPURLResponse: fetch() проверяет response.ok, а у URLResponse
        // статус нулевой — сайт молча выбрасывал конфиг с фичами.
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": type,
                                                  "Content-Length": String(data.count)])!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - мост к наушникам по RFCOMM

final class SerialBridge: NSObject, IOBluetoothRFCOMMChannelDelegate {
    /// Куда уходят события канала. Мост не знает, кто на той стороне: сегодня
    /// это чужой сайт в `WKWebView`, завтра — нативные экраны. Кадры отдаются
    /// байтами, а не гексом: гекс нужен только шиму, пусть он его и делает.
    var onOpened: (_ ok: Bool, _ reason: String) -> Void = { _, _ in }
    var onReceive: (_ frame: [UInt8]) -> Void = { _ in }
    var onClosed: () -> Void = {}

    /// Имя и адрес устройства, к которому открыт канал. Имя показывается как
    /// есть, а по адресу лежит кэш опознания — по нему узнаётся модель и цвет.
    private(set) var deviceName: String?
    private(set) var deviceAddress: String?

    private var channel: IOBluetoothRFCOMMChannel?
    private var opening = false
    private var isOpen = false                 // канал ГОТОВ, а не просто создан
    private var lastUUID = SPP_UUID            // куда переподключаться
    private var outbox: [(uuid: String, frame: [UInt8], at: Date)] = []   // кадры, ждущие открытия
    private var generation = 0                 // номер попытки подключения
    private var reconnecting = false           // восстановление после обрыва, а не запрос сайта
    private var inbox = [UInt8]()              // склейка входящего потока в кадры

    // Все три события уходят через одну очередь: порядок доставки держится
    // на этом, а не на том, из какого потока пришёл колбэк IOBluetooth.
    private func opened(_ ok: Bool, _ reason: String = "") {
        DispatchQueue.main.async { self.onOpened(ok, reason) }
    }
    private func received(_ frame: [UInt8]) {
        DispatchQueue.main.async { self.onReceive(frame) }
    }

    func open(uuidString: String, retry: Bool = true) {
        guard channel == nil else { trace("open: канал уже открыт"); opened(true); return }
        if opening && retry { trace("open: подключение уже идёт, повторный запрос игнорирую"); return }
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            trace("open: pairedDevices() = nil (нет доступа к Bluetooth)")
            if reconnecting { notifyClosed() } else { opened(false, "нет доступа к Bluetooth") }
            return
        }
        lastUUID = uuidString
        generation += 1
        trace("open: сервис \(uuidString), сопряжённых устройств \(paired.count), retry=\(retry)")
        let uuid = IOBluetoothSDPUUID(data: Data(stride(from: 0, to: 32, by: 2).map { i -> UInt8 in
            let h = uuidString.replacingOccurrences(of: "-", with: "")
            let idx = h.index(h.startIndex, offsetBy: i)
            return UInt8(h[idx...h.index(idx, offsetBy: 1)], radix: 16)!
        }))
        for device in paired {
            let name = device.name ?? "?"
            guard let rec = device.getServiceRecord(for: uuid) else {
                trace("  \(name): сервиса \(uuidString) нет в кэше SDP")
                continue
            }
            var chID: BluetoothRFCOMMChannelID = 0
            guard rec.getRFCOMMChannelID(&chID) == kIOReturnSuccess else {
                trace("  \(name): сервис есть, RFCOMM-канала нет"); continue
            }
            var ch: IOBluetoothRFCOMMChannel?
            let rc = device.openRFCOMMChannelAsync(&ch, withChannelID: chID, delegate: self)
            trace("  \(name): канал \(chID), openRFCOMMChannelAsync → \(rc)")
            if rc == kIOReturnSuccess {
                channel = ch
                opening = true
                deviceName = device.name
                deviceAddress = device.addressString
                // Канал опознания устройство отдаёт только сразу после подключения:
                // если молчит — подставляем сохранённый ответ прошлого раза.
                if uuidString == FASTPAIR_UUID { scheduleFastpairFallback(address: device.addressString ?? "?") }
                return
            }
            opened(false, "канал \(chID): ошибка \(rc)"); return
        }
        // Кэш SDP пуст, пока устройство не опрошено — спрашиваем и пробуем ещё раз.
        if retry {
            trace("open: сервис не найден, запускаю performSDPQuery")
            for device in paired where (device.name ?? "").lowercased().contains("nothing") {
                device.performSDPQuery(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.open(uuidString: uuidString, retry: false) }
            return
        }
        trace("open: сервис так и не найден")
        if reconnecting { notifyClosed() }
        else { opened(false, "устройство с нужным сервисом не найдено — включено ли оно и сопряжено?") }
    }

    private func scheduleFastpairFallback(address: String) {
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            // Только своя попытка: иначе таймер от опознания гасит уже идущее
            // подключение к каналу управления.
            guard let self, self.opening, self.generation == mine,
                  self.lastUUID == FASTPAIR_UUID else { return }
            self.opening = false
            guard let hex = UserDefaults.standard.string(forKey: "fastpair-\(address)") else {
                trace("FastPair: канал не открылся, сохранённого опознания нет")
                self.opened(false, "канал опознания недоступен — переподключите наушники и попробуйте снова")
                return
            }
            trace("FastPair: канал молчит, подставляю сохранённое опознание \(hex)")
            self.opened(true)
            self.received(hexBytes(hex))
        }
    }

    /// Обрыв канала: пробуем восстановить сами и только при неудаче сообщаем сайту.
    /// Иначе штатный обрыв по простою выкидывает пользователя на выбор устройства,
    /// а очередь отложенных кадров теряет смысл.
    private func handleLostChannel() {
        isOpen = false
        channel = nil
        inbox.removeAll()
        reconnecting = true
        open(uuidString: lastUUID)
    }

    /// Сообщаем сайту, что сессия кончилась: без этого его читающий цикл
    /// (while (port.readable) { await reader.read() }) висит вечно.
    private func notifyClosed() {
        reconnecting = false
        outbox.removeAll()
        DispatchQueue.main.async { self.onClosed() }
    }

    /// Шим шлёт гекс — разбираем на границе и дальше живём байтами.
    func write(hex: String) { write(hexBytes(hex)) }

    func write(_ bytes: [UInt8]) {
        guard isOpen, let ch = channel else {
            // Устройство закрывает канал на простое: копим кадр и переоткрываем.
            trace("write: канал закрыт, ставлю кадр в очередь и переподключаюсь")
            enqueue(bytes)
            if !opening { channel = nil; open(uuidString: lastUUID) }
            return
        }
        var buf = bytes
        let rc = ch.writeSync(&buf, length: UInt16(buf.count))
        if rc == kIOReturnSuccess { trace("→ \(hexString(bytes))") }
        if rc != kIOReturnSuccess {
            trace("write: ошибка \(rc), кадр в очередь, переподключаюсь")
            enqueue(bytes)
            ch.close()          // иначе объект остаётся делегатом и его колбэк отбросит guard
            handleLostChannel()
        }
    }

    private static let outboxLimit = 32
    private static let frameTTL: TimeInterval = 25   // больше таймаута открытия канала в шиме (15 с)

    private func enqueue(_ frame: [UInt8]) {
        outbox.append((uuid: lastUUID, frame: frame, at: Date()))
        if outbox.count > Self.outboxLimit {
            outbox.removeFirst(outbox.count - Self.outboxLimit)
            trace("очередь переполнена, старые кадры отброшены")
        }
    }

    private func flushOutbox() {
        guard isOpen, let ch = channel, !outbox.isEmpty else { return }
        let now = Date()
        // Команда имеет смысл только сразу: протухшие не отправляем, иначе после
        // часа простоя залпом вернём старые режимы ANC/EQ поверх новых.
        let (fresh, stale) = outbox.reduce(into: ([(uuid: String, frame: [UInt8], at: Date)](), 0)) { acc, item in
            if item.uuid == lastUUID && now.timeIntervalSince(item.at) <= Self.frameTTL { acc.0.append(item) } else { acc.1 += 1 }
        }
        outbox.removeAll()
        var sent = 0
        for item in fresh {
            var frame = item.frame
            if ch.writeSync(&frame, length: UInt16(frame.count)) == kIOReturnSuccess { sent += 1 }
            else { trace("flush: кадр не ушёл") }
        }
        trace("flush: отправлено \(sent), отброшено устаревших/чужих \(stale)")
    }

    func close() {
        opening = false
        isOpen = false
        inbox.removeAll()
        outbox.removeAll()
        // Обнуляем ССЫЛКУ ДО закрытия, а не после. Иначе `rfcommChannelClosed`
        // успевает прийти, пока поле ещё указывает на этот канал, проходит
        // проверку «свой ли» и трактуется как ОБРЫВ: мост уходит в режим
        // восстановления, и следующее удачное открытие он уже никому не
        // сообщает — `openComplete` там молча уходит в ветку reconnecting.
        // Наше собственное закрытие обрывом не является, и после обнуления
        // тот же колбэк честно опознаётся как посторонний.
        let closing = channel
        channel = nil
        closing?.close()
    }

    func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        // Колбэк брошенного канала не должен трогать состояние живого.
        guard ch === channel else { trace("openComplete от постороннего канала, игнорирую"); return }
        opening = false
        trace("openComplete: статус \(status), MTU \(ch?.getMTU() ?? 0)")
        if status == kIOReturnSuccess {
            isOpen = true
            if reconnecting { trace("канал восстановлен"); reconnecting = false }
            else { opened(true) }
            flushOutbox()
        }
        else {
            channel = nil; isOpen = false
            if reconnecting { trace("восстановить канал не удалось"); notifyClosed() }
            else { opened(false, "статус \(status)") }
        }
    }
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data: UnsafeMutableRawPointer!, length: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: data, count: length))

        // Канал опознания говорит не нашим протоколом: отдаём доставку как есть.
        // Кэшируем ТОЛЬКО отсюда — на канале управления семибайтным бывает хвост
        // недособранного кадра, и он однажды затёр кэш мусором.
        if lastUUID == FASTPAIR_UUID {
            let hex = hexString(bytes)
            trace("← опознание \(hex)")
            if length == 7, let addr = ch?.getDevice()?.addressString {
                UserDefaults.standard.set(hex, forKey: "fastpair-\(addr)")
                trace("опознание сохранено для \(addr)")
            }
            received(bytes)
            return
        }

        // Канал управления: RFCOMM склеивает и режет кадры, их парсер такого не
        // переживает — собираем по длине из заголовка и отдаём ровно по одному.
        inbox.append(contentsOf: bytes)
        while inbox.count >= 8 {
            guard inbox[0] == 0x55, inbox[1] == 0x60 else { inbox.removeFirst(); continue }
            let total = 8 + Int(inbox[5]) + 2
            guard inbox.count >= total else { break }
            let frame = Array(inbox.prefix(total))
            inbox.removeFirst(total)
            trace("← \(hexString(frame))")
            received(frame)
        }
    }

    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
        guard ch === channel else { trace("закрылся посторонний канал, игнорирую"); return }
        trace("канал закрыт устройством, пробую восстановить")
        handleLostChannel()
    }
}

// MARK: - приложение

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let bridge = SerialBridge()

    var native: NativeWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        // Нативный экран стал основным: обычный запуск идёт в него, а чужой
        // сайт остаётся под флагом `--web` — он всё ещё умеет то, до чего
        // нативный слой пока не дорос (пространственный звук, две пары,
        // детекция в ухе, кодек, персональный звук).
        if !CommandLine.arguments.contains("--web") {
            trace("=== старт: нативный экран ===")
            // Сохранённая тема применяется ДО разбора отладочных флагов,
            // чтобы --dark и --light оставались сильнее настройки.
            Appearance.shared.apply()
            // Тему система переключает глобально, а смотреть надо обе.
            // Отладочный флаг, как --selftest; в обычном запуске приложение
            // следует системе и ничего не навязывает.
            if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            if CommandLine.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
            native = NativeWindow()
            native?.show()
            return
        }
        trace("=== старт ===")
        let res = Bundle.main.resourceURL!
        let shim = (try? String(contentsOf: res.appendingPathComponent("shim.js"), encoding: .utf8)) ?? ""

        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(SiteHandler(root: { SiteStore.activeSite() }), forURLScheme: SCHEME)
        cfg.userContentController.addUserScript(
            WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // Сайт глушит console.log, если в адресе нет ?debug — а после перехода на
        // страницу устройства его там нет. Возвращаем перехват уже после их кода.
        cfg.userContentController.addUserScript(
            WKUserScript(source: "window.__rehookConsole && window.__rehookConsole();",
                         injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        cfg.userContentController.add(self, name: "serial")

        // Окно создаём ДО webView: иначе страница верстается под нулевую ширину
        // и остаётся в мобильной раскладке.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 860),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = titleText()
        window.center()

        webView = WKWebView(frame: window.contentLayoutRect, configuration: cfg)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        wireBridgeToSite()
        window.contentView = webView
        if SiteStore.activeSite() != nil {
            webView.load(URLRequest(url: URL(string: "\(SCHEME)://site/index.html?debug=1")!))
        } else {
            // Первый запуск из исходников: чужих файлов в репозитории нет, копия качается сама.
            trace("копии сайта нет — качаю при первом запуске")
            webView.loadHTMLString(
                "<body style=\"background:#21201f;color:#eee;font:15px -apple-system;display:flex;"
                + "align-items:center;justify-content:center;height:100vh;margin:0;text-align:center\">"
                + "Первый запуск: загружаю интерфейс с earweb.bttl.xyz…</body>", baseURL: nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let pruned = SiteStore.prune(keeping: SiteStore.downloadedSites().first?.lastPathComponent)
        if pruned > 0 { trace("старт: убрано лишних каталогов \(pruned)") }
        trace("старт: активна \(SiteStore.activeLabel())")
        checkForSiteUpdate()
    }

    /// Перевод событий моста в вызовы шима. Единственное место, где транспорт
    /// встречается с вебом; нативным экранам понадобится свой такой же.
    private func wireBridgeToSite() {
        bridge.onOpened = { [weak self] ok, reason in
            self?.webView.evaluateJavaScript("window.__serialOpened(\(ok), \(jsString(reason)))")
        }
        bridge.onReceive = { [weak self] frame in
            self?.webView.evaluateJavaScript("window.__serialRecv('\(hexString(frame))')")
        }
        bridge.onClosed = { [weak self] in
            self?.webView.evaluateJavaScript("window.__serialClosed && window.__serialClosed()")
        }
    }

    private func titleText() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "Unofficial driver for Nothing audio devices \(v)"
    }

    /// Тихая проверка: нет сети — молча работаем на том, что вшито.
    private func checkForSiteUpdate() {
        // --force-update качает копию, даже если размеры совпали (проверка и ручное обновление).
        let forced = CommandLine.arguments.contains("--force-update")
        SiteUpdater.checkForUpdate { [weak self] hasUpdate in
            guard hasUpdate || forced else { trace("обновление: актуально"); return }
            if forced { trace("обновление: принудительное скачивание") }
            trace("обновление: на сайте есть свежая версия, качаю")
            SiteUpdater.download { ok, message in
                trace("обновление: \(message)")
                guard ok, let self else { return }
                self.window.title = self.titleText()
                self.webView.load(URLRequest(url: URL(string: "\(SCHEME)://site/index.html?debug=1")!))
                trace("обновление: применено, страница перезагружена")
            }
        }
    }

    func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
        trace("страница загружена: \(w.url?.absoluteString ?? "?")")
        guard CommandLine.arguments.contains("--selftest"),
              w.url?.path.contains("index.html") == true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            trace("selftest: вызываю scanNewDevicesFastpair()")
            w.evaluateJavaScript("scanNewDevicesFastpair(); void 0;") { _, err in
                if let err { trace("selftest: ошибка вызова — \(err)") }
            }
        }
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return }
        if op == "log" { trace("js: \(body["msg"] as? String ?? "")"); return }
        trace("js → \(op)")
        switch op {
        case "open":  bridge.open(uuidString: (body["uuid"] as? String) ?? SPP_UUID)
        // Кадр не логируем здесь: `SerialBridge.write` пишет `→` сам, и только
        // когда кадр действительно ушёл. Две строки на одну запись сбивают с толку.
        case "write": if let hex = body["hex"] as? String { bridge.write(hex: hex) }
        case "close": bridge.close()
        default: break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
