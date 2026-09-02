#!/usr/bin/env bash
#
# Run the same shellcheck CI runs, locally, via Docker -- so a lint failure is
# caught before tagging rather than after, when the tag already exists and has
# to be deleted and recreated.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mapfile -t files < <(
    find paseo/rootfs/usr/local/bin -type f -printf '/mnt/%p\n'
    find paseo/rootfs/usr/local/sbin -type f -printf '/mnt/%p\n'
    find paseo/rootfs/etc/profile.d -type f -name '*.sh' -printf '/mnt/%p\n'
    find scripts -type f -name '*.sh' -printf '/mnt/%p\n'
)

docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable \
    --severity=warning "${files[@]}"
printf '\033[32mshellcheck clean (%d files)\033[0m\n' "${#files[@]}"
