#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
carve_photos.py —— 从 TF 卡 / 磁盘镜像里"抠"出照片（file carving），流式扫描，不需要中间镜像

特点：
  - 边读边抠，128G 的卡不需要 128G 的镜像空间，只要放得下恢复出来的照片
  - JPEG 按段结构解析定边界（不是简单找 FFD8/FFD9），误报少、文件大小准
  - HEIC/MP4/MOV 按 box 链解析定边界
  - 支持断点续扫（Ctrl+C 或手机杀后台后，重跑同一条命令自动接着扫）
  - 支持 --limit 只扫一部分（先试水，确认能出图再全扫）
  - 纯标准库，pip 什么都不用装

用法：
    # 1) 先试水：只扫前 2GB，看看能不能出图
    python3 carve_photos.py /dev/block/mmcblk1 ~/recovered --limit 2G

    # 2) 确认有效后全扫
    python3 carve_photos.py /dev/block/mmcblk1 ~/recovered

    # 只抠 JPEG，且只要大于 100KB 的（过滤缩略图），显示进度更频繁
    python3 carve_photos.py sdcard.img ~/recovered --only jpg --min-size 100000

参数：
    source       块设备（/dev/block/mmcblk1）或镜像文件（sdcard.img）
    outdir       输出目录，绝对不能是源卡本身
    --only       类型，逗号分隔：jpg,png,heic,mp4,mov,avi,wav（默认 jpg,png,heic,avi）
    --min-size   小于该字节数的丢弃（默认 8192；想要原图建议 50000~100000）
    --limit      只扫前 N 字节，支持 K/M/G/T 后缀
    --resume     断点续扫状态文件（默认 outdir/.carve_state.json）
    --max-file-size  单个 avi/wav 的大小上限，支持 K/M/G（默认 120M）
                 视频动辄几百 MB，手机内存有限，超过上限的直接跳过不恢复

AVI / WAV 说明：
  - 两者都是 RIFF 容器：'RIFF' + 4字节LE长度 + 4字节类型，长度就写在头部，
    不用像 JPEG 那样逐字节找结尾，判定边界很快
  - 但删过的卡上长度字段可能本身是脏的，所以加了校验：类型必须是 'AVI '/'WAVE'，
    AVI 后面要跟一个正常的块头，长度不能离谱
  - 单个 AVI 越大越容易跨过扫描段边界（默认 10GB 一段）被截断，真要救长视频
    就把每段调大；不过有 120M 上限挡着，实际影响有限
"""

import argparse
import hashlib
import json
import os
import signal
import sys
import time

# ---------------- 文件头特征 ----------------
SIGNATURES = [
    (b"\xff\xd8\xff", "jpg"),
    (b"\x89PNG\r\n\x1a\n", "png"),
    (b"\x00\x00\x00\x18ftypheic", "heic"),
    (b"\x00\x00\x00\x18ftypheix", "heic"),
    (b"\x00\x00\x00\x18ftypmif1", "heic"),
    (b"\x00\x00\x00\x18ftypmsf1", "heic"),
    (b"\x00\x00\x00\x18ftyphevc", "heic"),
    (b"\x00\x00\x00\x18ftypisom", "mp4"),
    (b"\x00\x00\x00\x18ftypmp42", "mp4"),
    (b"\x00\x00\x00\x1cftypqt  ", "mov"),
    (b"RIFF", "avi"),      # AVI / WAV 共用 RIFF 容器，具体是哪一种在 RiffParser 里区分
]
PNG_END = b"IEND\xaeB`\x82"

BLOCK = 4 * 1024 * 1024        # 每次读 4MB
ALIGN = 4096                   # 块设备读取对齐
ABANDON = 48 * 1024 * 1024     # 单个文件攒到 48MB 还没结尾 → 判定坏文件，放弃
PROGRESS_EVERY = 32 * 1024 * 1024


def parse_size(s):
    s = s.strip().upper()
    units = {"K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4}
    if s and s[-1] in units:
        return int(float(s[:-1]) * units[s[-1]])
    return int(s)


def human(n):
    for u in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or u == "TB":
            return f"{n:.1f}{u}"
        n /= 1024


# ---------------- JPEG 增量解析 ----------------
class JpegParser:
    """从 SOI 起按段结构增量推进，返回 EOI 之后的绝对偏移；数据不够返回 None；结构坏返回 -1"""

    def __init__(self, start_abs):
        self.i = start_abs + 2        # 跳过 SOI (FFD8)
        self.in_scan = False

    def feed(self, buf, base, limit_abs):
        """推进解析，最多到 limit_abs。返回：结束绝对偏移 / None(数据不够) / -1(结构坏)"""
        end_buf = len(buf) + base     # buf 覆盖到这个绝对偏移
        top = min(limit_abs, end_buf)
        while self.i < top - 1:
            rel = self.i - base
            if rel < 0:
                return -1
            if self.in_scan:
                # 熵编码数据区：跳到下一个 0xFF
                k = buf.find(b"\xff", rel, top - base)
                if k == -1:
                    self.i = top
                    return None
                self.i = base + k
                if self.i + 1 >= top:
                    return None
                n = buf[k + 1]
                if n == 0x00 or 0xD0 <= n <= 0xD7:      # 转义 FF00 / 重启标记
                    self.i += 2
                    continue
                if n == 0xFF:                            # 填充字节
                    self.i += 1
                    continue
                if n == 0xD9:                            # EOI
                    return self.i + 2
                self.in_scan = False                     # 遇到其它标记 → 回到段解析
                rel = self.i - base
            if buf[rel] != 0xFF:
                return -1                                # 段链断了
            m = buf[rel + 1]
            if m == 0xFF:
                self.i += 1
                continue
            if m == 0xD9:
                return self.i + 2
            if m == 0x00:
                return -1
            self.i += 2
            if m == 0x01 or 0xD0 <= m <= 0xD7:
                continue
            if m == 0xDA:                                # SOS → 进入熵编码数据区
                self.in_scan = True
                continue
            if self.i + 2 > top:
                return None
            ln = int.from_bytes(buf[self.i - base:self.i - base + 2], "big")
            if ln < 2 or self.i + ln > top:
                if self.i + ln > end_buf:
                    return None                          # 段长度超出已读数据，等更多数据
                return -1
            self.i += ln
        return None


# ---------------- ISO-BMFF (HEIC/MP4/MOV) box 链解析 ----------------
class BoxParser:
    """按 box(长度+类型) 链推进到文件结束。返回结束绝对偏移 / None / -1"""

    def __init__(self, start_abs):
        self.i = start_abs
        self.start = start_abs
        self.ok = False

    @staticmethod
    def _plausible(typ):
        return all((48 <= c <= 57) or (97 <= c <= 122) or (65 <= c <= 90)
                   or c in (32, 45, 46, 95) for c in typ)

    def feed(self, buf, base, limit_abs):
        top = min(limit_abs, len(buf) + base)
        while self.i + 8 <= top:
            rel = self.i - base
            size = int.from_bytes(buf[rel:rel + 4], "big")
            typ = bytes(buf[rel + 4:rel + 8])
            hdr = 8
            if size == 1:                                # 64 位长度
                if self.i + 16 > top:
                    return None
                size = int.from_bytes(buf[rel + 8:rel + 16], "big")
                hdr = 16
            if size == 0:                                # 到文件末尾
                return top
            if size < hdr or not self._plausible(typ):
                # box 链断在文件末尾 → 前面解析到的就是完整文件
                return self.i if self.ok else -1
            if self.i + size > top:
                return None                              # 等更多数据
            self.i += size
            self.ok = True
        return None


class PngParser:
    def __init__(self, start_abs):
        self.start = start_abs

    def feed(self, buf, base, limit_abs):
        rel = self.start - base
        p = buf.find(PNG_END, max(rel + 8, 0), len(buf))
        if p != -1:
            return base + p + len(PNG_END)
        return None


# ---------------- RIFF (AVI / WAV) 解析 ----------------
RIFF_TYPES = (b"AVI ", b"WAVE")
AVI_NEXT_OK = (b"LIST", b"JUNK", b"idx1", b"RIFF", b"AVIX", b"movi")


class RiffParser:
    """RIFF 容器：'RIFF' + 4字节LE长度(不含前8字节) + 4字节类型。
    长度写在头部，所以能一步算出文件结尾，不用攒数据慢慢找。"""

    def __init__(self, start_abs, max_span=120 * 1024 * 1024):
        self.start = start_abs
        self.max_span = max_span
        self.span_limit = max_span          # 主流程据此决定攒到多大就放弃
        self.kind = "avi"                   # 读到类型后改成 avi / wav

    def feed(self, buf, base, limit_abs):
        rel = self.start - base
        if rel < 0:
            return -1
        if rel + 12 > len(buf):
            return None                     # 头部还没读全，等数据

        if bytes(buf[rel:rel + 4]) != b"RIFF":
            return -1
        ftype = bytes(buf[rel + 8:rel + 12])
        if ftype not in RIFF_TYPES:
            return -1                       # 不是 AVI / WAV
        self.kind = "wav" if ftype == b"WAVE" else "avi"

        size = int.from_bytes(buf[rel + 4:rel + 8], "little")
        if size < 24:
            return -1                       # 太小，不可能是真文件

        end = self.start + 8 + size
        if end - self.start > self.max_span:
            return -1                       # 超过上限：直接放弃，别把内存吃光

        # AVI 头后面紧跟的应该是个正常块头，否则多半是误报
        if ftype == b"AVI " and rel + 16 <= len(buf):
            if bytes(buf[rel + 12:rel + 16]) not in AVI_NEXT_OK:
                return -1

        if end > limit_abs:
            return None                     # 结尾还没读到，等更多数据
        return end


def make_parser(kind, start_abs, max_span=120 * 1024 * 1024):
    if kind == "jpg":
        return JpegParser(start_abs)
    if kind == "png":
        return PngParser(start_abs)
    if kind in ("avi", "wav"):
        return RiffParser(start_abs, max_span)
    return BoxParser(start_abs)


# ---------------- 主流程 ----------------
def carve(src, outdir, only, min_size, limit, state_path, total_hint=None,
          max_file_size=120 * 1024 * 1024):
    os.makedirs(outdir, exist_ok=True)
    sigs = [s for s in SIGNATURES if s[1] in only]
    # 视频动辄上百 MB，给 RIFF 单独放宽"攒数据"的上限，其余类型仍用 ABANDON
    max_span = max(max_file_size, ABANDON) if ("avi" in only or "wav" in only) else ABANDON

    stream = (src == "-" or src == "/dev/stdin")
    if stream:
        # 管道模式：配合 scsi_dump 边读卡边抠，不需要几百 G 的中间镜像
        fd = 0
        total = None
        try:
            import fcntl
            fcntl.fcntl(fd, fcntl.F_SETFL, os.O_NONBLOCK)
            fcntl.fcntl(fd, fcntl.F_SETFL, 0)
        except Exception:
            pass
        print("源: stdin（管道流式输入）")
    else:
        fd = os.open(src, os.O_RDONLY)
        try:
            total = os.lseek(fd, 0, os.SEEK_END) if os.path.isfile(src) else None
            if total is None:
                try:
                    import fcntl
                    buf = bytearray(8)
                    fcntl.ioctl(fd, 0x80081272, buf, True)  # BLKGETSIZE64
                    total = int.from_bytes(bytes(buf), "little")
                except Exception:
                    total = None
            os.lseek(fd, 0, os.SEEK_SET)
        except Exception:
            total = None
    if total is None and total_hint:
        total = total_hint
    if limit and (total is None or limit < total):
        total = limit

    # 输出目录剩余空间检查
    st = os.statvfs(outdir)
    free = st.f_bavail * st.f_frsize
    print(f"源: {src}   大小: {human(total) if total else '未知'}")
    print(f"输出目录可用空间: {human(free)}")
    if free < 2 * 1024**3:
        print("  ! 可用空间不足 2GB，恢复大文件时可能中途写满，建议先清理")

    # 断点续扫状态
    state = {"base": 0, "kind": None, "start": 0, "count": 0}
    if stream:
        # 管道无法回退，续扫只能靠 scsi_dump 的 -s 参数从指定 LBA 重来
        print("（管道模式不支持断点续扫，如需中断请记录进度后改用什么参数重跑）")
        try:
            if os.path.exists(state_path):
                os.remove(state_path)
        except Exception:
            pass
    elif os.path.exists(state_path):
        try:
            state.update(json.load(open(state_path)))
            print(f"发现续扫状态，从第 {human(state['base'])} 处继续（已恢复 {state['count']} 个）")
        except Exception:
            print("续扫状态损坏，从头开始")

    seen = set()
    count = state["count"]

    def save(payload, kind, off):
        nonlocal count
        if len(payload) < min_size:
            return False
        h = hashlib.md5(payload).hexdigest()
        if h in seen:
            return False
        seen.add(h)
        name = f"{kind}_{count:06d}_{off}.{kind}"
        with open(os.path.join(outdir, name), "wb") as o:
            o.write(payload)
        count += 1
        return True

    base = (state["base"] // ALIGN) * ALIGN
    buf = bytearray()
    scan_abs = base
    cur = None
    if state["kind"]:
        cur = {"kind": state["kind"], "start": state["start"],
               "parser": make_parser(state["kind"], state["start"], max_span)}
        scan_abs = max(state["start"], base)

    last_report = 0
    t0 = time.time()
    eof = False
    stop = False

    def on_sigint(sig, frm):
        nonlocal stop
        stop = True
        print("\n收到中断，正在保存进度…")

    signal.signal(signal.SIGINT, on_sigint)

    pos = base
    while True:
        if stop:
            break
        if limit and pos >= limit:
            eof = True
            break
        want = BLOCK
        if limit:
            want = min(want, limit - pos)
        try:
            if stream:
                # 管道可能一次给不满，循环补齐
                parts, got = [], 0
                while got < want:
                    c = os.read(fd, want - got)
                    if not c:
                        break
                    parts.append(c)
                    got += len(c)
                chunk = b"".join(parts)
            else:
                chunk = os.pread(fd, want, pos)
        except OSError as e:
            print(f"\n读取失败 @{pos}: {e}")
            break
        if not chunk:
            eof = True
            break
        pos += len(chunk)
        buf = buf + bytearray(chunk) if buf else bytearray(chunk)

        eff_end = len(buf) + base          # buf 覆盖到的绝对偏移

        while True:
            if cur is None:
                # 找下一个文件头
                best = None
                for sig, k in sigs:
                    j = buf.find(sig, scan_abs - base)
                    if j != -1 and (best is None or j < best[0]):
                        best = (j, k, len(sig))
                if best is None:
                    scan_abs = eff_end
                    break
                j, k, slen = best
                st_abs = base + j
                cur = {"kind": k, "start": st_abs,
                       "parser": make_parser(k, st_abs, max_span)}
                continue

            r = cur["parser"].feed(buf, base, eff_end)
            if r is None:                                   # 数据不够，等下一块
                if eff_end - cur["start"] > getattr(cur["parser"], "span_limit", ABANDON):
                    scan_abs = cur["start"] + 3
                    cur = None
                    continue
                break
            if r == -1:                                     # 结构坏，从这里继续找
                scan_abs = cur["start"] + 3
                cur = None
                continue
            # 成功收尾
            rel = cur["start"] - base
            kind = getattr(cur["parser"], "kind", cur["kind"])
            save(bytes(buf[rel:r - base]), kind, cur["start"])
            scan_abs = r
            cur = None
            continue

        # 裁剪缓冲区，防止内存无限增长
        if cur is None:
            keep = scan_abs - base
            if keep > 0:
                buf = bytearray(buf[keep:])
                base += keep
            else:
                buf = bytearray()
        else:
            keep = cur["start"] - base
            if keep > 0:
                buf = bytearray(buf[keep:])
                base += keep
        scan_abs = max(scan_abs, base)

        # 进度 + 定期存状态
        if pos - last_report >= PROGRESS_EVERY or eof:
            last_report = pos
            done = min(pos, total) if total else pos
            pct = f"{done / total * 100:.1f}%" if total else "?"
            spd = pos / max(time.time() - t0, 1) / 1024**2
            print(f"  {human(done)}/{human(total) if total else '?'} ({pct})  "
                  f"已恢复 {count} 个  {spd:.1f}MB/s", flush=True)
            json.dump({"base": base, "kind": cur["kind"] if cur else None,
                       "start": cur["start"] if cur else 0, "count": count},
                      open(state_path, "w"))

    json.dump({"base": base, "kind": cur["kind"] if cur else None,
               "start": cur["start"] if cur else 0, "count": count},
              open(state_path, "w"))
    if not stream:
        os.close(fd)
    print(f"\n结束：本次扫到 {human(pos)}，累计恢复 {count} 个 -> {outdir}")
    print(f"耗时 {(time.time() - t0) / 60:.1f} 分钟")
    if not eof and not stop and not stream:
        print("（未扫完，重跑同一条命令会接着扫）")
    if not stream:
        print("提示：确认照片没问题后，可删除 " + state_path)


def main():
    ap = argparse.ArgumentParser(description="流式 file carving，从 TF 卡或镜像恢复照片")
    ap.add_argument("source", help="块设备 /dev/block/mmcblk1、镜像 sdcard.img，或 - 表示 stdin 管道")
    ap.add_argument("outdir", help="输出目录（绝不能是源卡本身）")
    ap.add_argument("--only", default="jpg,png,heic,avi",
                    help="类型，逗号分隔：jpg,png,heic,mp4,mov,avi,wav（默认 jpg,png,heic,avi）")
    ap.add_argument("--min-size", type=int, default=8192, help="最小字节数，默认 8192")
    ap.add_argument("--limit", default=None, help="只扫前 N，如 2G")
    ap.add_argument("--total", default=None, help="源总大小（仅用于显示进度百分比），如 500G")
    ap.add_argument("--state", default=None, help="续扫状态文件路径")
    ap.add_argument("--max-file-size", default=None,
                    help="单个 avi/wav 的大小上限，支持 K/M/G 后缀（默认 120M）")
    args = ap.parse_args()

    only = set(x.strip() for x in args.only.split(",") if x.strip())
    outdir = os.path.expanduser(args.outdir)
    state_path = args.state or os.path.join(outdir, ".carve_state.json")
    limit = parse_size(args.limit) if args.limit else None

    if args.source not in ("-", "/dev/stdin") and not os.path.exists(args.source):
        sys.exit(f"源不存在：{args.source}")

    total_hint = parse_size(args.total) if args.total else None
    max_file_size = parse_size(args.max_file_size) if args.max_file_size else 120 * 1024 * 1024
    if ("avi" in only or "wav" in only):
        print(f"视频/音频模式：单个文件上限 {human(max_file_size)}，更大的会跳过")
    carve(args.source, outdir, only, args.min_size, limit, state_path, total_hint,
          max_file_size)


if __name__ == "__main__":
    main()
