#!/usr/bin/env bash
set -euo pipefail
if command -v terraform >/dev/null 2>&1; then terraform version | head -1; exit 0; fi
VERSION=1.17.1
ARCH=$(uname -m)
case "$ARCH" in x86_64) ARCH=amd64;; aarch64) ARCH=arm64;; *) echo "Unsupported architecture: $ARCH"; exit 1;; esac
FILE="terraform_${VERSION}_linux_${ARCH}.zip"
BASE="https://releases.hashicorp.com/terraform/${VERSION}"
mkdir -p "$HOME/.local/bin"
curl -fsSL "$BASE/$FILE" -o "/tmp/$FILE"
curl -fsSL "$BASE/terraform_${VERSION}_SHA256SUMS" -o "/tmp/terraform_SHA256SUMS"
(cd /tmp && grep " $FILE\$" terraform_SHA256SUMS | sha256sum -c -)
unzip -qo "/tmp/$FILE" terraform -d "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
echo "Installed: $(terraform version | head -1)"
echo 'For future sessions run: export PATH="$HOME/.local/bin:$PATH"'
