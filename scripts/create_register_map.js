// ==UserScript==
// @name         Arm Docs to Zig
// @namespace    http://tampermonkey.net/
// @version      2025-01-31
// @description  try to take over the world!
// @author       xq
// @match        https://developer.arm.com/documentation/dui0552/a/cortex-m3-peripherals/*
// @icon         https://www.google.com/s2/favicons?sz=64&domain=arm.com
// @grant        none
// ==/UserScript==

(function() {
    'use strict';

    console.log("hi");

    function load_tables()
    {
        const tables = document.querySelectorAll("table.c-table");

        for(const _table of tables)
        {
            const table = _table;
            const caption = _table.querySelector("caption");
            console.log(caption);

            const button = document.createElement("button");
            button.type = "button";
            button.addEventListener("click", (ev) => {
                console.log("clicked");

                var tobject = {
                    rows: [],
                };

                const rows = table.rows;
                for(const row of rows)
                {
                    const cells = row.cells;

                    const robject = {
                        cells: [],
                    };
                    for(const cell of cells)
                    {
                        console.log(cell);
                        robject.cells.push(cell.innerText);
                    }
                    tobject.rows.push(robject);
                }

                console.log(tobject);
                console.log(JSON.stringify(tobject));
                navigator.clipboard.writeText(JSON.stringify(tobject));

            });
            button.innerText = "Generate Code";

            caption.insertBefore(button, caption.firstChild);
        }
    }

    setTimeout(load_tables, 1500);

    // Your code here...
})();