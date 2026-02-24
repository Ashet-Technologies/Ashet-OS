"use strict";

const percent1dp = new Intl.NumberFormat("en", {
    style: "percent",
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
});

const fsizeFormat = new Intl.NumberFormat("en", {
    style: "unit",
    unit: "byte",
    unitDisplay: "short",
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
});

class AshetTerminal extends Terminal {
    constructor(options) {
        console.log("original options:", options)
        options.rows = 10;
        options.fontSize = 10;
        options.disableStdin = true;
        console.log("new options:", options)
        super(options);


        this.fitAddon = new FitAddon.FitAddon();
        super.loadAddon(this.fitAddon);
    }

    open(element) {
        super.open(element);
        this.fitAddon.fit();
    }
}


class DownloadProgress {
    constructor(filename) {
        let file_status = document.createElement("li");
        file_status.innerHTML = `
					<meter data-id="meter" max="100" value="10">10%</meter>
					<label data-id="fname">???</label> (<span data-id="percent">0%</span> of <span data-id="fsize">??? kB</span>)
				`;

        this.meter = file_status.querySelector('[data-id="meter"]');
        this.fname = file_status.querySelector('[data-id="fname"]');
        this.percent = file_status.querySelector('[data-id="percent"]');
        this.fsize = file_status.querySelector('[data-id="fsize"]');

        this.fname.textContent = filename;

        this.element = file_status;
    }

    update(loaded, total) {
        let perc = loaded / total;

        let percLocale = percent1dp.format(perc);

        this.meter.value = loaded;
        this.meter.max = total;

        this.meter.textContent = percLocale;
        this.percent.textContent = percLocale;
        this.fsize.textContent = fsizeFormat.format(total);
    }
}

function launch_emulator() {
    let emulator_status = document.getElementById("emulator_status");
    let serial_console = document.getElementById("serial_console");
    let screen_container = document.getElementById("screen_container");

    // let term = new Terminal({
    // 	rows: 10
    // });
    // term.open(serial_console);
    // term.write('Hello from \x1B[1;3;31mxterm.js\x1B[0m $ ')

    var emulator = window.emulator = new V86({
        wasm_path: "v86/v86.wasm",
        memory_size: 32 * 1024 * 1024,
        vga_memory_size: 2 * 1024 * 1024,
        screen_container: screen_container,
        bios: {
            url: "bios/seabios.bin",
        },
        vga_bios: {
            url: "bios/vgabios.bin",
        },
        // cdrom: {
        //     url: "images/livedemo.iso",
        // },
        hda: {
            url: "images/livedemo.img",
        },
        autostart: true,

        serial_console: {
            type: "xtermjs",
            xterm_lib: AshetTerminal,
            container: serial_console,
        },
    });


    // export type Event =
    //     | "9p-attach"
    //     | "9p-read-end"
    //     | "9p-read-start"
    //     | "9p-write-end"
    //     | "download-error"
    //     | "download-progress"
    //     | "emulator-loaded"
    //     | "emulator-ready"
    //     | "emulator-started"
    //     | "emulator-stopped"
    //     | "eth-receive-end"
    //     | "eth-transmit-end"
    //     | "ide-read-end"
    //     | "ide-read-start"
    //     | "ide-write-end"
    //     | "mouse-enable"
    //     | "net0-send"
    //     | "screen-put-char"
    //     | "screen-set-size"
    //     | "serial0-output-byte"
    //     | "virtio-console0-output-bytes";

    for (const evt of [
        "download-error",
        "emulator-loaded",
        "emulator-ready",
        "emulator-started",
        "emulator-stopped",
    ]) {
        let copy = evt;
        emulator.add_listener(evt, (event) => console.log("event", evt, event));
    }

    const progressMap = {}

    function update_progress(event) {
        emulator_status.style.display = undefined;

        let progress = progressMap[event.file_index];
        if (progress == null) {
            progress = new DownloadProgress(event.file_name);
            progressMap[event.file_index] = progress;

            emulator_status.insertBefore(progress.element, emulator_status.firstChild)
        }
        progress.update(event.loaded, event.total);
    }

    function onEmulatorReady() {
        emulator_status.style.display = 'none';
    }

    emulator.add_listener('download-progress', update_progress);
    emulator.add_listener('emulator-ready', onEmulatorReady);

    window.start_vm = function () {
        emulator.run();
    };

    window.stop_vm = function () {
        emulator.stop();
    };

    window.restart_vm = function () {
        emulator.restart();
    };
}