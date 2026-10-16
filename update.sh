#!/usr/bin/env bash
set -e

# Move to the script's directory
cd "$(dirname "$(readlink -f "$0")")"

# Fetch latest release info from GitHub API
release_json=$(curl -fsS "https://api.github.com/repos/abelnotes/abelnotes/releases/latest")
latest_tag=$(echo "$release_json" | jq -r '.tag_name' | sed 's/^v//')
deb_url=$(echo "$release_json" | jq -r '[.assets[] | select(.name | endswith(".deb"))][0].browser_download_url')

current_ver=$(grep -E '^pkgver=' PKGBUILD | cut -d= -f2)

if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
    echo "Error: Could not retrieve latest release from GitHub."
    exit 1
fi

if [ "$latest_tag" != "$current_ver" ]; then
    echo "New version found: $latest_tag (current: $current_ver)"

    # Derive the build suffix from the .deb filename (abelnotes_<ver>-<build>_amd64.deb)
    deb_name=$(basename "$deb_url")
    build=${deb_name#abelnotes_${latest_tag}-}
    build=${build%_amd64.deb}
    if [ "$build" = "$deb_name" ] || [ -z "$build" ]; then
        echo "Error: could not parse build suffix from $deb_name"
        exit 1
    fi

    # Update version and build suffix in PKGBUILD
    sed -i "s/^pkgver=.*/pkgver=$latest_tag/" PKGBUILD
    sed -i "s/^pkgrel=.*/pkgrel=1/" PKGBUILD
    sed -i "s|^_build=.*|_build=\"$build\"|" PKGBUILD

    # Refresh checksums
    updpkgsums

    # Regenerate .SRCINFO
    makepkg --printsrcinfo > .SRCINFO

    echo "PKGBUILD and .SRCINFO updated to $latest_tag."
    echo "Building and installing with paru..."
    paru -Bi .
else
    echo "AbelNotes is already up to date ($current_ver)."
fi
