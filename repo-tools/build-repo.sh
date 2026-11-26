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

mkdir -p debs

# ---- 1. Докачать пакеты по списку extras.txt ------------------------------
# Формат строки:  <URL> | <имя файла>
# Строки с # — комментарии. Скачивание идёт с серверов GitHub (не из РФ),
# поэтому медленные/заблокированные у провайдера адреса здесь обычно качаются.
if [ -f extras.txt ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    url="$(echo "${line%%|*}" | sed 's/[[:space:]]*$//')"
    name="$(echo "${line#*|}" | sed 's/^[[:space:]]*//')"
    if [ "$name" = "$line" ] || [ -z "$name" ]; then
      name="$(basename "$url")"
    fi
    if [ -f "debs/$name" ]; then
      echo "extras: уже в репозитории — $name"
      continue
    fi
    echo "extras: качаю $name"
    if curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 --max-time 300 \
         -A "Sileo/2.5 CFNetwork/1335.0.3 Darwin/21.6.0" -o "debs/$name" "$url"; then
      if head -c 7 "debs/$name" | grep -q '!<arch>'; then
        echo "extras: OK $(du -h "debs/$name" | cut -f1)"
      else
        echo "extras: $name не является .deb — удаляю"
        rm -f "debs/$name"
      fi
    else
      echo "extras: НЕ удалось скачать $url (пропускаю, сборка продолжится)"
      rm -f "debs/$name"
    fi
  done < extras.txt
fi

# ---- 2. Проверка, что есть что индексировать ------------------------------
shopt -s nullglob
debs=(debs/*.deb)
if [ ${#debs[@]} -eq 0 ]; then
  echo "В debs/ нет ни одного .deb — нечего индексировать" >&2
  exit 1
fi

# ---- 3. Сборка индекса ----------------------------------------------------
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
