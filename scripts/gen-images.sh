#!/usr/bin/env bash
#
# Render the add-on icon and logo PNGs from their SVG sources.
# Home Assistant wants icon.png square (256px is plenty) and logo.png wider.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../paseo"

rsvg-convert -w 256 -h 256 icon.svg -o icon.png
rsvg-convert -w 640 -h 220 logo.svg -o logo.png

printf 'wrote %s\n' paseo/icon.png paseo/logo.png
