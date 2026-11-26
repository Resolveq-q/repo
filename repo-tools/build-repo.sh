#!/usr/bin/env bash
# build-repo.sh — сборка индекса репозитория на Linux-раннере GitHub Actions
# (используется в .github/workflows/build-repo.yml; локально тоже работает в WSL/git-bash)
set -euo pipefail

OUT="${1:-_site}"
ORIGIN="${REPO_ORIGIN:-Personal Jailbreak Repo}"
LABEL="${REPO_LABEL:-Personal Jailbreak Repo}"
DESC="${REPO_DESC:-Personal Sileo/Zebra source (iPhone 7+, iOS 15)}"

command -v dpkg-scanpackages >/dev/null 2>&1 || {
  echo "dpkg-scanpackages не найден. Debian/Ubuntu: sudo apt-get install -y dpkg-dev" >&2
  exit 1
}

shopt -s nullglob
debs=(debs/*.deb)
if [ ${#debs[@]} -eq 0 ]; then
  echo "В debs/ нет ни одного .deb — нечего индексировать" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/debs"
cp debs/*.deb "$OUT/debs/"

cd "$OUT"
dpkg-scanpackages -m debs /dev/null > Packages
gzip -9 -n -c Packages > Packages.gz

ARCHS="$(grep -h '^Architecture: ' Packages | awk '{print $2}' | sort -u | tr '\n' ' ' | sed 's/ $//')"

{
  echo "Origin: $ORIGIN"
  echo "Label: $LABEL"
  echo "Suite: stable"
  echo "Version: 1.0"
  echo "Codename: ios"
  echo "Architectures: $ARCHS"
  echo "Components: main"
  echo "Description: $DESC"
} > Release

for algo in MD5Sum:md5sum SHA1:sha1sum SHA256:sha256sum; do
  key="${algo%%:*}"; tool="${algo##*:}"
  echo "$key:"
  for f in Packages Packages.gz; do
    printf ' %s %s %s\n' "$("$tool" "$f" | cut -d' ' -f1)" "$(stat -c%s "$f")" "$f"
  done
done >> Release

touch .nojekyll

echo "Готово: $OUT ($(grep -c '^Package: ' Packages) записей, архитектуры: $ARCHS)"
