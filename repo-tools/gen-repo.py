#!/usr/bin/env python3
r"""
gen-repo.py — собирает индекс APT-репозитория (Sileo / Zebra / Cydia) из папки debs/.

Что делает:
  1. читает заголовки (control) прямо из .deb (это ar-архив),
  2. пишет Packages (и Packages.gz),
  3. пишет Release с контрольными суммами,
  4. копирует .deb в выходную папку.

Использование (Windows):
    python repo-tools\gen-repo.py              # debs/  ->  _site/
    python repo-tools\gen-repo.py --out site   # другая выходная папка

Результат (_site/) — это ровно то, что должно лежать в корне GitHub Pages.
"""

import argparse
import gzip
import hashlib
import io
import lzma
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEBS = os.path.join(ROOT, "debs")

ORIGIN = os.environ.get("REPO_ORIGIN", "Personal Jailbreak Repo")
LABEL = os.environ.get("REPO_LABEL", "Personal Jailbreak Repo")
DESCRIPTION = os.environ.get("REPO_DESC", "Personal Sileo/Zebra source (iPhone 7+, iOS 15)")

# Поля, которые должны идти первыми в записи Packages
LEADING = ["Package", "Version", "Architecture", "Maintainer", "Depends", "Pre-Depends",
           "Recommends", "Conflicts", "Replaces", "Provides", "Section", "Priority",
           "Installed-Size", "Filename", "Size", "MD5sum", "SHA1", "SHA256", "Name",
           "Author", "Description"]


# ---------------------------------------------------------------- .deb reading
def ar_members(path):
    """Вернуть список (name, bytes) из ar-архива .deb."""
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("это не ar-архив (.deb)")
    pos, members = 8, []
    while pos + 60 <= len(data):
        header = data[pos:pos + 60]
        name = header[0:16].decode("ascii", "replace").strip().rstrip("/")
        size_field = header[48:58].decode("ascii", "replace").strip()
        if not size_field.isdigit():
            break
        size = int(size_field)
        start = pos + 60
        members.append((name, data[start:start + size]))
        pos = start + size + (size % 2)
    return members


def read_control(deb_path):
    """Достать текст control-файла из .deb."""
    for name, blob in ar_members(deb_path):
        if not name.startswith("control.tar"):
            continue
        # 1) обычные форматы: tar, tar.gz, tar.xz — их понимает tarfile
        for mode in ("r:*", "r:"):
            try:
                with tarfile.open(fileobj=io.BytesIO(blob), mode=mode) as tf:
                    for m in tf.getmembers():
                        if os.path.basename(m.name) == "control":
                            return tf.extractfile(m).read().decode("utf-8", "replace")
            except Exception:
                pass
        # 2) zstd (Python < 3.14 его не умеет) — пробуем системный bsdtar
        try:
            with tempfile.TemporaryDirectory() as td:
                raw = os.path.join(td, name)
                with open(raw, "wb") as f:
                    f.write(blob)
                out = subprocess.run(["tar", "-xOf", raw, "./control"],
                                     capture_output=True, check=True).stdout
                return out.decode("utf-8", "replace")
        except Exception:
            pass
    raise RuntimeError("не найден control внутри .deb (нужен zstd/tar? )")


def parse_control(text):
    """Разобрать control в dict с сохранением порядка (продолжения строк — с пробелом)."""
    fields, last = {}, None
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        if not line.strip():
            continue
        if line[0] in " \t" and last:
            fields[last] += "\n" + line[1:]
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            last = k.strip()
            fields[last] = v.strip()
    return fields


# ---------------------------------------------------------------- hashing
def sums(path):
    h_md5, h_sha1, h_sha256 = hashlib.md5(), hashlib.sha1(), hashlib.sha256()
    size = 0
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            size += len(chunk)
            h_md5.update(chunk)
            h_sha1.update(chunk)
            h_sha256.update(chunk)
    return size, h_md5.hexdigest(), h_sha1.hexdigest(), h_sha256.hexdigest()


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="_site", help="выходная папка (по умолчанию _site)")
    args = ap.parse_args()

    out = args.out if os.path.isabs(args.out) else os.path.join(ROOT, args.out)
    out_debs = os.path.join(out, "debs")

    if not os.path.isdir(DEBS):
        sys.exit(f"нет папки {DEBS}")

    deb_files = sorted(f for f in os.listdir(DEBS) if f.lower().endswith(".deb"))
    if not deb_files:
        sys.exit("в debs/ нет ни одного .deb — нечего индексировать")

    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out_debs)

    entries, problems = [], []
    for fn in deb_files:
        src = os.path.join(DEBS, fn)
        dst = os.path.join(out_debs, fn)
        shutil.copy2(src, dst)

        try:
            fields = parse_control(read_control(src))
        except Exception as exc:                                     # noqa: BLE001
            problems.append(f"{fn}: {exc}")
            continue

        for req in ("Package", "Version", "Architecture"):
            if not fields.get(req):
                problems.append(f"{fn}: нет обязательного поля {req}")
                break
        else:
            size, md5, sha1, sha256 = sums(dst)
            fields["Filename"] = f"debs/{fn}"
            fields["Size"] = str(size)
            fields["MD5sum"] = md5
            fields["SHA1"] = sha1
            fields["SHA256"] = sha256
            fields["Priority"] = fields.get("Priority", "optional")
            fields["Section"] = fields.get("Section", "Tweaks")
            if fields["Architecture"] not in ("iphoneos-arm", "iphoneos-arm64", "all"):
                problems.append(f"{fn}: неожиданная архитектура {fields['Architecture']}")
            entries.append(fields)

    if not entries:
        sys.exit("не удалось разобрать ни один пакет:\n  " + "\n  ".join(problems))

    entries.sort(key=lambda e: (e["Package"], e["Architecture"]))
    chunks = []
    for e in entries:
        keys = [k for k in LEADING if k in e] + [k for k in e if k not in LEADING]
        chunks.append("\n".join(f"{k}: {e[k]}" for k in keys))
    packages_txt = "\n\n".join(chunks) + "\n"

    pkg_path = os.path.join(out, "Packages")
    with open(pkg_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(packages_txt)
    with open(pkg_path + ".gz", "wb") as f:
        f.write(gzip.compress(packages_txt.encode("utf-8"), 9, mtime=0))

    index_files = ["Packages", "Packages.gz"]
    archs = sorted({e["Architecture"] for e in entries})
    release = [
        f"Origin: {ORIGIN}",
        f"Label: {LABEL}",
        "Suite: stable",
        "Version: 1.0",
        "Codename: ios",
        f"Architectures: {' '.join(archs)}",
        "Components: main",
        f"Description: {DESCRIPTION}",
    ]
    for algo, key in (("md5", "MD5Sum"), ("sha1", "SHA1"), ("sha256", "SHA256")):
        release.append(f"{key}:")
        for name in index_files:
            h = hashlib.new(algo.replace("md5", "md5"))
            p = os.path.join(out, name)
            with open(p, "rb") as f:
                data = f.read()
            h.update(data)
            release.append(f" {h.hexdigest()} {len(data)} {name}")
    with open(os.path.join(out, "Release"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(release) + "\n")

    with open(os.path.join(out, ".nojekyll"), "w", encoding="utf-8") as f:
        f.write("")

    print(f"Готово: {out}")
    print(f"  пакетов в индексе: {len(entries)}  (архитектуры: {', '.join(archs)})")
    for e in entries:
        print(f"   - {e['Package']} v{e['Version']} [{e['Architecture']}]")
    if problems:
        print("\nПроблемы:")
        for p in problems:
            print(f"  ! {p}")


if __name__ == "__main__":
    main()
