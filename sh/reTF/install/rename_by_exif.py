#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rename_by_exif.py —— 把 carve 出来的一堆编号文件整理成人能看的照片库

做四件事：
  1. 按 EXIF 里的拍摄时间重命名成 20240315_142530.jpg
  2. 按年月建子目录（2024-03/），方便按时间找回
  3. md5 去重（carving 经常抠出重复片段和缩略图）
  4. 把打不开/不完整的挑到 _broken/，把小于指定大小的缩略图挑到 _thumbs/

用法：
    python3 rename_by_exif.py ~/recovered ~/照片_已恢复
    python3 rename_by_exif.py ~/recovered ~/照片_已恢复 --min-size 50000 --no-subdir

纯标准库，不用装 Pillow。只处理 jpg（png/heic 没有 EXIF 时间就按文件顺序命名）。
"""

import argparse
import hashlib
import os
import shutil
import struct
import sys
from collections import Counter

EXIF_IFD = 0x8769
TAG_DT_ORIG = 0x9003      # DateTimeOriginal
TAG_DT = 0x0132           # DateTime


def read_exif_datetime(data):
    """从 JPEG 二进制里读拍摄时间，返回 'YYYY:MM:DD HH:MM:SS' 或 None"""
    if data[:2] != b"\xff\xd8":
        return None
    i = 2
    n = len(data)
    while i < n - 3:
        if data[i] != 0xFF:
            return None
        m = data[i + 1]
        if m == 0xD9 or m == 0xDA:
            return None                                  # EXIF 只在文件头部
        i += 2
        if m in (0x01,) or 0xD0 <= m <= 0xD7:
            continue
        ln = int.from_bytes(data[i:i + 2], "big")
        if ln < 2 or i + ln > n:
            return None
        if m == 0xE1 and data[i + 2:i + 8] == b"Exif\x00\x00":
            tiff = data[i + 8:i + ln]
            return _parse_tiff(tiff)
        i += ln
    return None


def _parse_tiff(tiff):
    if len(tiff) < 8:
        return None
    bo = tiff[:2]
    if bo == b"II":
        e = "little"
    elif bo == b"MM":
        e = "big"
    else:
        return None
    try:
        if int.from_bytes(tiff[2:4], e) != 42:
            return None
        off = int.from_bytes(tiff[4:8], e)
        found = {}

        def walk(ifd_off, depth=0):
            if depth > 2 or ifd_off + 2 > len(tiff):
                return
            cnt = int.from_bytes(tiff[ifd_off:ifd_off + 2], e)
            for k in range(cnt):
                p = ifd_off + 2 + k * 12
                if p + 12 > len(tiff):
                    return
                tag = int.from_bytes(tiff[p:p + 2], e)
                typ = int.from_bytes(tiff[p + 2:p + 4], e)
                cnt2 = int.from_bytes(tiff[p + 4:p + 8], e)
                sz = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8}.get(typ, 1) * cnt2
                if sz <= 4:
                    val = tiff[p + 8:p + 8 + sz]
                else:
                    vo = int.from_bytes(tiff[p + 8:p + 12], e)
                    if vo + sz > len(tiff):
                        continue
                    val = tiff[vo:vo + sz]
                if tag in (TAG_DT_ORIG, TAG_DT) and tag not in found:
                    s = val.split(b"\x00")[0].decode("ascii", "ignore").strip()
                    if len(s) >= 19:
                        found[tag] = s
                if tag == EXIF_IFD and len(val) >= 2:
                    walk(int.from_bytes(val[:2], e), depth + 1)

        walk(off)
    except Exception:
        return None
    return found.get(TAG_DT_ORIG) or found.get(TAG_DT)


def valid_jpeg(path):
    """能否被正常解码：SOI 开头、EOI 结尾、段链不断"""
    try:
        with open(path, "rb") as f:
            head = f.read(4)
            if head[:2] != b"\xff\xd8":
                return False
            f.seek(0, 2)
            size = f.tell()
            if size < 1024:
                return False
            f.seek(-2, 2)
            return f.read(2) == b"\xff\xd9"
    except Exception:
        return False


def valid_png(path):
    try:
        with open(path, "rb") as f:
            if f.read(8) != b"\x89PNG\r\n\x1a\n":
                return False
            f.seek(-8, 2)
            return f.read(8) == b"IEND\xaeB`\x82"
    except Exception:
        return False


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description="按 EXIF 时间整理恢复出来的照片")
    ap.add_argument("srcdir", help="carve 输出目录")
    ap.add_argument("dstdir", help="整理后的目录")
    ap.add_argument("--min-size", type=int, default=20000,
                    help="小于此字节数视为缩略图，默认 20000")
    ap.add_argument("--no-subdir", action="store_true", help="不建年月子目录")
    ap.add_argument("--copy", action="store_true", help="复制而非移动（更安全）")
    args = ap.parse_args()

    src = os.path.expanduser(args.srcdir)
    dst = os.path.expanduser(args.dstdir)
    for d in (dst, os.path.join(dst, "_broken"), os.path.join(dst, "_thumbs")):
        os.makedirs(d, exist_ok=True)

    files = sorted(f for f in os.listdir(src)
                   if f.lower().endswith((".jpg", ".jpeg", ".png", ".heic")))
    if not files:
        sys.exit(f"{src} 里没有图片文件")

    seen = set()
    stat = Counter()
    used = Counter()

    for i, fn in enumerate(files):
        p = os.path.join(src, fn)
        size = os.path.getsize(p)
        h = md5(p)
        if h in seen:
            stat["重复丢弃"] += 1
            continue
        seen.add(h)

        ext = os.path.splitext(fn)[1].lower()
        if size < args.min_size:
            shutil.move(p, os.path.join(dst, "_thumbs", fn))
            stat["缩略图"] += 1
            continue
        ok = valid_jpeg(p) if ext in (".jpg", ".jpeg") else (
            valid_png(p) if ext == ".png" else True)
        if not ok:
            shutil.move(p, os.path.join(dst, "_broken", fn))
            stat["损坏"] += 1
            continue

        dt = None
        if ext in (".jpg", ".jpeg"):
            with open(p, "rb") as f:
                dt = read_exif_datetime(f.read(256 * 1024))

        if dt and len(dt) >= 19:
            d, t = dt[:10].replace(":", ""), dt[11:19].replace(":", "")
            sub = f"{d[:4]}-{d[4:6]}"
            stem = f"{d}_{t}"
        else:
            sub, stem = "无时间", f"noexif_{i:05d}"

        target_dir = dst if args.no_subdir else os.path.join(dst, sub)
        os.makedirs(target_dir, exist_ok=True)
        used[stem] += 1
        name = stem if used[stem] == 1 else f"{stem}_{used[stem]}"
        target = os.path.join(target_dir, name + ext)
        k = 1
        while os.path.exists(target):
            target = os.path.join(target_dir, f"{name}_{k}{ext}")
            k += 1

        (shutil.copy2 if args.copy else shutil.move)(p, target)
        stat["已整理"] += 1
        if stat["已整理"] % 200 == 0:
            print(f"  已整理 {stat['已整理']}/{len(files)}", flush=True)

    print("\n===== 整理完成 =====")
    for k, v in stat.items():
        print(f"  {k}: {v}")
    print(f"输出目录：{dst}")
    print("  _broken/ = 不完整打不开的，_thumbs/ = 太小的缩略图")


if __name__ == "__main__":
    main()
