/*
 * scsi_dump.c —— 通过 termux-usb 拿到的 fd，用 libusb 直接给 USB 读卡器发
 *                SCSI READ(10) 命令，把 TF 卡的原始扇区读出来。
 *
 * 为什么需要它：无 root 时 SELinux 挡住块设备节点，dd 直接 Permission denied。
 *               但 termux-usb 走的是 Android 官方 USB 授权通道，拿到的是已经打开的
 *               fd，libusb 可以直接 wrap 它，从而绕过文件系统逐扇区读卡。
 *
 * 编译：
 *   pkg install clang libusb
 *   clang -O2 -o scsi_dump scsi_dump.c -lusb-1.0
 *
 * 用法：
 *   # 先看卡容量（fd 由 termux-usb -e 以 $1 传入）
 *   termux-usb -r -e './scsi_dump %FD% --info' /dev/bus/usb/001/002
 *
 *   # 整卡镜像到文件
 *   termux-usb -r -e './scsi_dump %FD% -o /sdcard/sd.img' /dev/bus/usb/001/002
 *
 *   # 只读前 4GB，输出到 stdout（可接管道，最省空间）
 *   termux-usb -r -e './scsi_dump %FD% -n 8388608 -o -' /dev/bus/usb/001/002
 *
 * 参数：
 *   fd            USB 设备文件描述符（termux-usb 传进来）
 *   -o PATH       输出路径，"-" 表示 stdout（默认 stdout）
 *   -s LBA        起始扇区，默认 0
 *   -n BLOCKS     读取扇区数，默认全部
 *   -b BLOCKS     每次 SCSI 命令读多少扇区，默认 128（64KB）
 *   --info        只打印容量信息后退出
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <libusb-1.0/libusb.h>

#define CBW_SIG 0x43425355  /* "USBC" little-endian */
#define CSW_SIG 0x53425355  /* "USBS" little-endian */
#define TIMEOUT 20000       /* ms，慢卡可能需要更长 */

#pragma pack(push, 1)
typedef struct {
    uint32_t sig;
    uint32_t tag;
    uint32_t len;
    uint8_t  flags;
    uint8_t  lun;
    uint8_t  cblen;
    uint8_t  cb[16];
} cbw_t;

typedef struct {
    uint32_t sig;
    uint32_t tag;
    uint32_t residue;
    uint8_t  status;
} csw_t;
#pragma pack(pop)

static libusb_device_handle *g_h = NULL;
static uint8_t g_ep_in = 0, g_ep_out = 0;
static uint32_t g_tag = 0x1234;
static int g_lun = 0;

static void die(const char *msg, int rc)
{
    fprintf(stderr, "错误: %s (libusb %d: %s)\n", msg, rc, libusb_error_name(rc));
    exit(2);
}

/* 发 CBW，需要往外传数据时额外发 data */
static int send_cbw(cbw_t *c, const uint8_t *data)
{
    int rc, transferred = 0;
    rc = libusb_bulk_transfer(g_h, g_ep_out, (uint8_t *)c, 31, &transferred, TIMEOUT);
    if (rc != 0 || transferred != 31) {
        fprintf(stderr, "CBW 发送失败 rc=%d 传了%d字节\n", rc, transferred);
        return -1;
    }
    if (c->len > 0 && data) {
        rc = libusb_bulk_transfer(g_h, g_ep_out, (uint8_t *)data, c->len, &transferred, TIMEOUT);
        if (rc != 0) return -1;
    }
    return 0;
}

/* 收数据 + 收 CSW，返回 CSW status（0=成功），-1 表示通信失败 */
static int recv_data_csw(uint8_t *buf, int want)
{
    int rc, got = 0, transferred = 0;
    csw_t csw;

    while (got < want) {
        rc = libusb_bulk_transfer(g_h, g_ep_in, buf + got, want - got, &transferred, TIMEOUT);
        if (rc != 0) {
            fprintf(stderr, "读数据失败 rc=%d (%s)，已收 %d/%d\n",
                    rc, libusb_error_name(rc), got, want);
            return -1;
        }
        if (transferred == 0) break;
        got += transferred;
    }

    transferred = 0;
    rc = libusb_bulk_transfer(g_h, g_ep_in, (uint8_t *)&csw, 13, &transferred, TIMEOUT);
    if (rc != 0) {
        fprintf(stderr, "读 CSW 失败 rc=%d\n", rc);
        return -1;
    }
    if (transferred != 13 || csw.sig != CSW_SIG || csw.tag != g_tag - 1) {
        fprintf(stderr, "CSW 校验失败 (sig=%08x tag=%u 收到%d字节)\n",
                csw.sig, csw.tag, transferred);
        return -1;
    }
    return csw.status;
}

/* SCSI READ CAPACITY(10) */
static int scsi_capacity(uint32_t *last_lba, uint32_t *block_size)
{
    cbw_t c;
    uint8_t data[8];
    memset(&c, 0, sizeof(c));
    c.sig = CBW_SIG;
    c.tag = g_tag++;
    c.len = 8;
    c.flags = 0x80;            /* data-in */
    c.lun = g_lun;
    c.cblen = 10;
    c.cb[0] = 0x25;            /* READ CAPACITY(10) */

    if (send_cbw(&c, NULL) != 0) return -1;
    if (recv_data_csw(data, 8) != 0) return -1;

    *last_lba = (uint32_t)((data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3]);
    *block_size = (uint32_t)((data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7]);
    return 0;
}

/* SCSI TEST UNIT READY */
static int scsi_ready(void)
{
    cbw_t c;
    memset(&c, 0, sizeof(c));
    c.sig = CBW_SIG;
    c.tag = g_tag++;
    c.len = 0;
    c.flags = 0x80;
    c.lun = g_lun;
    c.cblen = 6;
    c.cb[0] = 0x00;            /* TEST UNIT READY */

    if (send_cbw(&c, NULL) != 0) return -1;
    return recv_data_csw(NULL, 0);
}

/* SCSI READ(10)，读到的数据写进 buf */
static int scsi_read10(uint32_t lba, uint16_t blocks, uint8_t *buf)
{
    cbw_t c;
    memset(&c, 0, sizeof(c));
    c.sig = CBW_SIG;
    c.tag = g_tag++;
    c.len = (uint32_t)blocks * 512;
    c.flags = 0x80;
    c.lun = g_lun;
    c.cblen = 10;
    c.cb[0] = 0x28;            /* READ(10) */
    c.cb[2] = (uint8_t)(lba >> 24);
    c.cb[3] = (uint8_t)(lba >> 16);
    c.cb[4] = (uint8_t)(lba >> 8);
    c.cb[5] = (uint8_t)(lba);
    c.cb[7] = (uint8_t)(blocks >> 8);
    c.cb[8] = (uint8_t)(blocks);

    if (send_cbw(&c, NULL) != 0) return -1;
    return recv_data_csw(buf, (int)blocks * 512);
}

/* 探测卡的真实可读范围：扩容卡超过真实容量后，读会报错或返回全 FF / 垃圾 */
static int probe_readable(uint32_t lba, uint8_t *buf)
{
    return scsi_read10(lba, 8, buf) == 0;
}

static void probe_card(uint64_t total_blocks, int nsamples)
{
    uint8_t *buf = malloc(256 * 512);
    if (!buf) { fprintf(stderr, "内存不足\n"); return; }
    if (nsamples < 2) nsamples = 2;
    if (nsamples > 256) nsamples = 256;

    fprintf(stderr, "采样 %d 个点（每点 128KB），判断卡的真实可读范围\n", nsamples);
    fprintf(stderr, "读错误的点每个最多等 %d 秒，请耐心\n\n", TIMEOUT / 1000);

    printf("%-6s %-12s %-10s %s\n", "序号", "LBA", "位置(GiB)", "状态");

    uint64_t last_good = 0;
    int first_bad = -1;

    for (int i = 0; i < nsamples; i++) {
        uint64_t lba = (uint64_t)((double)i * (double)(total_blocks - 1)
                                  / (double)(nsamples - 1));
        uint16_t n = 256;
        if (lba + n > total_blocks) n = (uint16_t)(total_blocks - lba);
        if (n < 1) n = 1;

        int st = scsi_read10((uint32_t)lba, n, buf);
        int len = n * 512;
        const char *status;

        if (st != 0) {
            status = "!!!! 读错误";
            if (first_bad < 0) first_bad = i;
        } else {
            last_good = lba;
            int all_zero = 1, all_ff = 1;
            for (int k = 0; k < len; k++) {
                if (buf[k] != 0x00) all_zero = 0;
                if (buf[k] != 0xFF) all_ff = 0;
            }
            if (all_zero)      status = "全0 (空白)";
            else if (all_ff)   status = "全FF (可疑)";
            else {
                int has_jpg = 0;
                for (int k = 0; k + 2 < len; k++) {
                    if (buf[k] == 0xFF && buf[k+1] == 0xD8 && buf[k+2] == 0xFF) {
                        has_jpg = 1; break;
                    }
                }
                status = has_jpg ? "有数据 ★含JPEG头" : "有数据";
            }
        }
        printf("%-6d %-12llu %-10.1f %s\n", i, (unsigned long long)lba,
               (double)lba * 512.0 / 1073741824.0, status);
        fflush(stdout);
    }

    printf("\n");
    if (first_bad < 0) {
        printf("结论: 全部采样点都能读出，未发现硬错误边界。\n");
        printf("      若看到大量「全FF」，仍可能是扩容卡（超出部分返回垃圾）\n");
    } else {
        /* 在最后一个好点和第一个坏点之间二分，找真实容量边界 */
        uint64_t lo = (uint64_t)((double)(first_bad - 1) * (double)(total_blocks - 1)
                                 / (double)(nsamples - 1));
        uint64_t hi = (uint64_t)((double)first_bad * (double)(total_blocks - 1)
                                 / (double)(nsamples - 1));
        fprintf(stderr, "发现读错误，在 LBA %llu ~ %llu 之间二分定位边界...\n",
                (unsigned long long)lo, (unsigned long long)hi);
        for (int it = 0; it < 24 && hi - lo > 1; it++) {
            uint64_t mid = lo + (hi - lo) / 2;
            if (probe_readable((uint32_t)mid, buf)) lo = mid;
            else hi = mid;
        }
        double real_gib = (double)lo * 512.0 / 1073741824.0;
        double real_gb  = (double)lo * 512.0 / 1e9;
        printf("结论: 真实可读容量约 LBA %llu = %.1f GiB (%.1f GB)\n",
               (unsigned long long)lo, real_gib, real_gb);
        printf("      卡标称 %.1f GiB，只有约 %.0f%% 是真的 → 这是一张扩容卡\n",
               (double)total_blocks * 512.0 / 1073741824.0,
               real_gib / ((double)total_blocks * 512.0 / 1073741824.0) * 100.0);
        printf("      照片只可能在这条线以内，扫前面这一段就够了\n");
        printf("\n建议命令（把 TOTAL_SECTORS 换成上面的 LBA 值）:\n");
        printf("  TOTAL_SECTORS=%llu SEG_GB=10 bash ~/seg_scan.sh\n",
               (unsigned long long)lo);
    }
    free(buf);
}

/* 找一个 bulk-in 和一个 bulk-out 端点 */
static void find_endpoints(void)
{
    libusb_device *dev = libusb_get_device(g_h);
    struct libusb_config_descriptor *cfg = NULL;
    if (libusb_get_active_config_descriptor(dev, &cfg) != 0) {
        /* 兜底值，绝大多数读卡器是 0x81 / 0x02 */
        g_ep_in = 0x81;
        g_ep_out = 0x02;
        return;
    }
    for (int i = 0; i < cfg->interface->altsetting->bNumEndpoints; i++) {
        const struct libusb_endpoint_descriptor *ep = &cfg->interface->altsetting->endpoint[i];
        if ((ep->bmAttributes & 0x03) != LIBUSB_TRANSFER_TYPE_BULK) continue;
        if (ep->bEndpointAddress & 0x80) g_ep_in = ep->bEndpointAddress;
        else                             g_ep_out = ep->bEndpointAddress;
    }
    libusb_free_config_descriptor(cfg);
    if (!g_ep_in)  g_ep_in = 0x81;
    if (!g_ep_out) g_ep_out = 0x02;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "用法: %s <fd> [-o 输出|-] [-s 起始LBA] [-n 扇区数] "
                        "[-b 每批扇区数] [--info] [--probe N] [--max-errors N]\n", argv[0]);
        return 1;
    }

    int fd = atoi(argv[1]);
    if (fd <= 0) {
        fprintf(stderr, "fd 无效: %s\n", argv[1]);
        return 1;
    }

    const char *outpath = "-";
    uint64_t start_lba = 0, nblocks = 0;
    int batch = 128;
    int info_only = 0;
    int probe_only = 0;
    int nsamples = 24;
    int max_errors = 256;      /* 连续读失败这么多次就判定设备掉线，直接退出 */

    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "-o") && i + 1 < argc)        outpath = argv[++i];
        else if (!strcmp(argv[i], "-s") && i + 1 < argc)   start_lba = strtoull(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "-n") && i + 1 < argc)   nblocks = strtoull(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "-b") && i + 1 < argc)   batch = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--info"))               info_only = 1;
        else if (!strcmp(argv[i], "--max-errors") && i + 1 < argc) max_errors = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--probe")) {
            probe_only = 1;
            if (i + 1 < argc && argv[i + 1][0] >= '0' && argv[i + 1][0] <= '9')
                nsamples = atoi(argv[++i]);
        }
    }
    if (batch < 1) batch = 128;
    if (batch > 65535) batch = 65535;

    /* 关键：禁止 libusb 去扫 /dev/bus/usb（无 root 会被 SELinux 拒绝），
       直接用 termux-usb 给的 fd */
    struct libusb_init_option opts[] = {
        { .option = LIBUSB_OPTION_NO_DEVICE_DISCOVERY, .value = { .ival = 1 } }
    };
    libusb_context *ctx = NULL;
    int rc = libusb_init_context(&ctx, opts, 1);
    if (rc != 0) die("libusb 初始化失败", rc);

    rc = libusb_wrap_sys_device(ctx, (intptr_t)fd, &g_h);
    if (rc != 0) die("包装 fd 失败（Termux 的 libusb 版本可能太旧）", rc);

    /* Android 侧可能还握着驱动，尝试 detach；失败不影响，接口通常已是我们的 */
    libusb_detach_kernel_driver(g_h, 0);

    rc = libusb_claim_interface(g_h, 0);
    if (rc != 0) fprintf(stderr, "警告: claim interface 失败 rc=%d，仍继续尝试\n", rc);

    find_endpoints();
    fprintf(stderr, "端点: IN=0x%02x OUT=0x%02x\n", g_ep_in, g_ep_out);

    /* 等卡就绪，读卡器刚插入时常常需要几秒 */
    int ready = -1;
    for (int i = 0; i < 30; i++) {
        ready = scsi_ready();
        if (ready == 0) break;
        usleep(500000);
    }
    if (ready != 0) fprintf(stderr, "警告: 设备未报 ready (status=%d)，继续尝试读\n", ready);

    uint32_t last_lba = 0, bs = 512;
    if (scsi_capacity(&last_lba, &bs) != 0) {
        fprintf(stderr, "读容量失败，卡可能没插好\n");
        return 3;
    }
    uint64_t total_blocks = (uint64_t)last_lba + 1;
    double gb = (double)total_blocks * bs / 1e9;
    fprintf(stderr, "容量: %llu 扇区 x %u 字节 = %.1f GB (%.0f GiB)\n",
            (unsigned long long)total_blocks, bs, gb,
            (double)total_blocks * bs / 1073741824.0);

    if (info_only) {
        printf("total_blocks=%llu block_size=%u\n", (unsigned long long)total_blocks, bs);
        return 0;
    }
    if (bs != 512 && bs != 4096) {
        fprintf(stderr, "警告: 扇区大小 %u 不常见，按 %u 处理\n", bs, bs);
    }

    if (start_lba >= total_blocks) {
        fprintf(stderr, "起始 LBA 超出范围\n");
        return 1;
    }
    if (nblocks == 0 || start_lba + nblocks > total_blocks)
        nblocks = total_blocks - start_lba;

    if (probe_only) {
        probe_card(total_blocks, nsamples);
        libusb_release_interface(g_h, 0);
        libusb_close(g_h);
        libusb_exit(ctx);
        return 0;
    }

    FILE *out = stdout;
    if (strcmp(outpath, "-") != 0) {
        out = fopen(outpath, "wb");
        if (!out) {
            fprintf(stderr, "打不开输出文件 %s: %s\n", outpath, strerror(errno));
            return 1;
        }
    }

    uint8_t *buf = malloc((size_t)batch * bs);
    if (!buf) { fprintf(stderr, "内存分配失败\n"); return 1; }

    fprintf(stderr, "开始读: LBA %llu 起，共 %llu 扇区，每批 %d\n",
            (unsigned long long)start_lba, (unsigned long long)nblocks, batch);

    uint64_t done = 0;
    time_t t0 = time(NULL);
    time_t last_report = t0;
    int consecutive_err = 0;
    int hard_fail = 0;         /* 连续硬失败计数 */
    int aborted = 0;

    while (done < nblocks) {
        uint32_t todo = (uint32_t)((nblocks - done) < (uint64_t)batch
                                   ? (nblocks - done) : (uint64_t)batch);
        uint32_t lba = (uint32_t)(start_lba + done);

        int st = scsi_read10(lba, (uint16_t)todo, buf);
        if (st != 0) {
            /* 降级重试：可能是单次传输太大 */
            if (todo > 1 && consecutive_err < 3) {
                fprintf(stderr, "  LBA %u 读取失败(status=%d)，降低批大小重试\n", lba, st);
                scsi_ready();
                if (batch > 8) batch = batch / 2;
                consecutive_err++;
                usleep(200000);
                continue;
            }
            hard_fail++;
            /* 卡掉线时每个 LBA 都会失败，若无限重试会把整个进程拖死，
               所以连续失败到上限就认定设备已断开（或已超出扩容卡真实容量） */
            if (max_errors > 0 && hard_fail >= max_errors) {
                fprintf(stderr, "\n!! 连续 %d 次读不出，判定设备已掉线或超出卡的真实容量，中止。\n",
                        hard_fail);
                fprintf(stderr, "   成功读出 %llu 扇区，中断于 LBA %llu（约 %.2f GiB 处）\n",
                        (unsigned long long)done, (unsigned long long)lba,
                        (double)lba * bs / 1073741824.0);
                aborted = 1;
                break;
            }
            if (hard_fail <= 3 || hard_fail % 50 == 0)
                fprintf(stderr, "  LBA %u 跳过（读不出，填零）连续失败 %d/%d\n",
                        lba, hard_fail, max_errors);
            memset(buf, 0, (size_t)todo * bs);
        } else {
            consecutive_err = 0;
            hard_fail = 0;
        }

        size_t w = fwrite(buf, 1, (size_t)todo * bs, out);
        if (w != (size_t)todo * bs) {
            fprintf(stderr, "写入失败（磁盘满了？）: %s\n", strerror(errno));
            break;
        }
        done += todo;

        time_t now = time(NULL);
        if (now - last_report >= 5) {
            double secs = difftime(now, t0);
            double mb = (double)done * bs / 1048576.0;
            fprintf(stderr, "  %.0f MB / %.0f MB  %.1f%%  %.1f MB/s\n",
                    mb, (double)nblocks * bs / 1048576.0,
                    (double)done / nblocks * 100.0,
                    secs > 0 ? mb / secs : 0);
            last_report = now;
            if (out != stdout) fflush(out);
        }
    }

    free(buf);
    if (out != stdout) fclose(out);
    else fflush(stdout);

    fprintf(stderr, "完成: 读出 %.1f MB，耗时 %.0f 秒\n",
            (double)done * bs / 1048576.0, difftime(time(NULL), t0));
    if (aborted)
        fprintf(stderr, "（异常中止，退出码 4；已读部分已写入，可从 LBA %llu 继续）\n",
                (unsigned long long)(start_lba + done));

    libusb_release_interface(g_h, 0);
    libusb_close(g_h);
    libusb_exit(ctx);
    return aborted ? 4 : 0;
}
