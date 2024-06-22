#!/bin/sh

set -e

root="$(realpath "$(dirname "$(realpath "$0")")"/../)"

cd "${root}"

clear

mkicon="${root}/zig-out/bin/tool_mkicon"
exicon="${root}/zig-out/bin/tool_extract_icon"
template="${root}/artwork/os/palette-evaluation/palette-evaluation.png"
outdir="${root}/artwork/os/palette-evaluation/output"

[ -x "${mkicon}" ]
[ -x "${exicon}" ]

for pal in "${root}/artwork/os/palette-evaluation/palettes/"*.gpl; do
    name="$(basename "${pal}")"
    echo "rendering $name..."

    "${mkicon}" -g 1600x1600 -o "${outdir}/${name}.abm" --palette "${pal}" "${template}"
    "${exicon}" -o "${outdir}/${name}.png" "${outdir}/${name}.abm"
    rm "${outdir}/${name}.abm"
done