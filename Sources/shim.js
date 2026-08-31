// Подменяет Web Serial API, которого нет в WebKit, мостом в нативный слой.
// Поверхность ровно та, что использует сайт: requestPort/getPorts + open/close/
// forget/opened/getInfo/readable/writable.
(() => {
    if (navigator.serial) return;

    const SPP_UUID = "aeac4a03-dff5-498f-843a-34487cf133eb";
    const post = (msg) => window.webkit.messageHandlers.serial.postMessage(msg);
    const trace = (msg) => post({ op: "log", msg: String(msg) });
    // Их собственные console.* — главный источник диагностики (страница
    // грузится с ?debug=1, иначе сайт глушит console.log).
    const hookConsole = () => {
    for (const level of ["log", "warn", "error"]) {
        const orig = console[level].bind(console);
        console[level] = (...a) => {
            try {
                trace(level + ": " + a.map((x) =>
                    x instanceof Error ? (x.name + ": " + x.message)     // JSON.stringify(Error) === "{}"
                    : typeof x === "object" ? JSON.stringify(x) : String(x)
                ).join(" ").slice(0, 300));
            } catch {}
            orig(...a);
        };
    }
    };
    hookConsole();
    window.__rehookConsole = hookConsole;
    window.addEventListener("error", (e) => trace("ошибка: " + e.message + " @ " + e.filename + ":" + e.lineno));
    window.addEventListener("unhandledrejection", (e) => trace("промис отклонён: " + e.reason));
    const toHex = (u8) => Array.from(u8, (b) => b.toString(16).padStart(2, "0")).join("");
    const fromHex = (h) => new Uint8Array(h.match(/../g).map((x) => parseInt(x, 16)));

    // Нативная сторона отдаёт по одному кадру на вызов — сайт именно так их и
    // читает (проверяет rawData[0] === 0x55 и разбирает целиком), поэтому
    // склеивать в поток нельзя.
    const frames = [];
    const waiters = [];
    window.__serialRecv = (hex) => {
        const chunk = fromHex(hex);
        const w = waiters.shift();
        if (w) w({ value: chunk, done: false });
        else frames.push(chunk);
    };

    // Попытки нумеруются: таймаут старой попытки не должен гасить новую.
    // Мост сообщает о закрытии канала — иначе читающий цикл сайта
    // (while (port.readable) { await reader.read() }) висит вечно.
    window.__serialClosed = () => {
        for (const p of ports.values()) p.opened = false;
        while (waiters.length) waiters.shift()({ value: new Uint8Array(0), done: true });
        frames.length = 0;
    };

    let openResolve = null, openAttempt = 0;
    window.__serialOpened = (ok, reason) => {
        const r = openResolve;
        openResolve = null;
        if (r) r({ ok, reason });
    };

    const makePort = (uuid) => ({
        opened: false,
        uuid,
        getInfo: () => ({ bluetoothServiceClassId: uuid }),
        async open() {
            trace("port.open()");
            const attempt = ++openAttempt;
            const res = await new Promise((resolve) => {
                openResolve = resolve;
                post({ op: "open", uuid: this.uuid });
                setTimeout(() => {
                    if (attempt === openAttempt) window.__serialOpened(false, "таймаут подключения");
                }, 15000);
            });
            if (!res.ok) throw new Error(res.reason || "не удалось открыть канал");
            this.opened = true;
        },
        async close() {
            trace("port.close()");
            this.opened = false;
            // Их цикл трогает value.length раньше проверки done, поэтому на
            // закрытии отдаём пустой массив, а не undefined.
            while (waiters.length) waiters.shift()({ value: new Uint8Array(0), done: true });
            post({ op: "close" });
        },
        async forget() { await this.close(); },
        get readable() {
            if (!this.opened) return null;          // сайт крутит while (sppPort.readable)
            return {
                getReader: () => ({
                    read: () => frames.length
                        ? Promise.resolve({ value: frames.shift(), done: false })
                        : new Promise((resolve) => waiters.push(resolve)),
                    releaseLock() {},
                    cancel: () => Promise.resolve(),
                }),
            };
        },
        get writable() {
            // Сайт берёт нового writer'а на каждую отправку и закрывает его —
            // с настоящим WritableStream так нельзя, поэтому close() здесь пустой.
            return {
                getWriter: () => ({
                    ready: Promise.resolve(),
                    write: async (u8) => post({ op: "write", hex: toHex(u8) }),
                    close: async () => {},
                    abort: async () => {},
                    releaseLock() {},
                }),
            };
        },
    });

    const ports = new Map();
    const portFor = (uuid) => {
        if (!ports.has(uuid)) ports.set(uuid, makePort(uuid));
        return ports.get(uuid);
    };

    trace("шим установлен");
    Object.defineProperty(navigator, "serial", {
        configurable: true,
        value: {
            requestPort: async (opts = {}) => {
                const uuid = opts.filters?.[0]?.bluetoothServiceClassId
                    || opts.allowedBluetoothServiceClassIds?.[0] || SPP_UUID;
                trace("requestPort() → сервис " + uuid);
                return portFor(uuid);
            },
            getPorts: async () => [portFor(SPP_UUID)],
            addEventListener() {},
            removeEventListener() {},
        },
    });
})();
