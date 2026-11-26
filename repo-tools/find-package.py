#!/usr/bin/env python3
"""
find-package.py — найти пакет в чужом репозитории и получить прямую ссылку на .deb.

Нужно, когда хочется добавить в свой репозиторий ещё какой-то твик: на iPhone
индекс не открывается (522), а на ПК — открывается.

Примеры:
    python repo-tools/find-package.py https://havoc.app "control center"
    python repo-tools/find-package.py https://sparkdev.me snowboard
    python repo-tools/find-package.py https://repo.chariz.com "gesture"

Печатает: имя пакета, версию, архитектуру, размер и прямую ссылку на .deb.
"""

import gzip
import io
import lzma
import re
import sys
import urllib.request

UA = {"User-Agent": "curl/8.5.0", "Accept": "*/*"}


def fetch_index(repo):
    repo = repo.rstrip("/") + "/"
    for suffix in ("Packages.gz", "Packages.xz", "Packages"):
        url = repo + suffix
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
        except Exception:
            continue
        try:
            if suffix.endswith(".gz"):
                raw = gzip.decompress(raw)
            elif suffix.endswith(".xz"):
                raw = lzma.decompress(raw)
        except Exception:
            continue
        if b"Package:" in raw[:500000]:
            return repo, raw.decode("utf-8", "replace")
    raise SystemExit(f"не удалось получить индекс из {repo}")


def entries(text):
    cur, last = {}, None
    for line in text.splitlines():
        if not line.strip():
            if cur:
                yield cur
            cur, last = {}, None
            continue
        if line[0] == " " and last:
            cur[last] += "\n" + line[1:]
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            cur[k.strip()] = v.strip()
            last = k.strip()
    if cur:
        yield cur


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    repo, pattern = sys.argv[1], sys.argv[2]
    base, text = fetch_index(repo)
    rx = re.compile(pattern, re.I)

    hits = []
    for e in entries(text):
        blob = " ".join([e.get("Package", ""), e.get("Name", ""), e.get("Description", "")[:300]])
        if rx.search(blob):
            fn = e.get("Filename", "")
            url = fn if fn.startswith("http") else base + fn.lstrip("./")
            hits.append((e.get("Package"), e.get("Version"), e.get("Architecture"),
                         e.get("Size", "?"), url, e.get("Tag", ""), e.get("Depends", "")))

    hits.sort()
    print(f"{base} — совпадений: {len(hits)}\n")
    for pkg, ver, arch, size, url, tag, dep in hits:
        paid = " [ПЛАТНЫЙ]" if "commercial" in tag else ""
        kb = f"{int(size)/1024:.0f} KB" if size.isdigit() else size
        print(f"{pkg}  v{ver}  [{arch}]  {kb}{paid}")
        print(f"    deps: {dep[:110]}")
        print(f"    {url}")


if __name__ == "__main__":
    main()
