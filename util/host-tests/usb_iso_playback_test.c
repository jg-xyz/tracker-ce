// Userspace isochronous playback test for the Polyend Tracker+ (16d0:1119).
//
// Purpose: separate "Linux snd-usb-audio / ALSA" from "xHCI + device". Streams a
// 440 Hz stereo S16 sine at 44.1 kHz to the UAC2 playback OUT endpoint (0x03)
// straight through usbfs, pacing packet sizes from the device's explicit feedback
// endpoint (0x83), and reports what actually reaches the wire:
//   * packets/s completed OK        (125 us microframes -> 8000 expected)
//   * frames/s                      (44100 expected)
//   * microframe gaps               (start_frame discontinuities = skipped microframes)
//   * iso packet errors
// If this holds ~8000 pkt/s, 0 gaps and ~44.1k frames/s while snd-usb-audio loses
// 25%, the fault is in the in-kernel audio driver, not xHCI/device.
//
// Needs root (usbfs node). Detaches snd-usb-audio from interface 2 for the run and
// re-attaches it afterwards. No external libraries.
//
// Build: cc -O2 -Wall -o usb_iso_playback_test usb_iso_playback_test.c
// Usage: sudo ./usb_iso_playback_test [seconds=10] [--nofeedback] [--urbs N] [--pkts N]

#include <errno.h>
#include <fcntl.h>
#include <linux/usbdevice_fs.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define VID 0x16d0
#define PID 0x1119
#define IFACE 2
#define ALT 1
#define EP_OUT 0x03
#define EP_FB 0x83
#define RATE 44100
#define NOMINAL_FB ((uint32_t)(((uint64_t)RATE << 16) / 8000)) // 16.16 samples/microframe
#define MAX_PKT_FRAMES 8
#define FB_PKTS 8

static int fd = -1;

static double now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static int read_sysfs_int(const char* dir, const char* name, int base)
{
    char path[512], buf[64];
    snprintf(path, sizeof path, "/sys/bus/usb/devices/%s/%s", dir, name);
    FILE* f = fopen(path, "r");
    if (!f)
        return -1;
    int ok = fgets(buf, sizeof buf, f) != NULL;
    fclose(f);
    return ok ? (int)strtol(buf, NULL, base) : -1;
}

static int find_device(int* bus, int* dev)
{
    char cmd[] = "ls /sys/bus/usb/devices";
    FILE* p = popen(cmd, "r");
    if (!p)
        return -1;
    char name[256];
    while (fgets(name, sizeof name, p))
    {
        name[strcspn(name, "\n")] = 0;
        if (read_sysfs_int(name, "idVendor", 16) == VID && read_sysfs_int(name, "idProduct", 16) == PID)
        {
            *bus = read_sysfs_int(name, "busnum", 10);
            *dev = read_sysfs_int(name, "devnum", 10);
            pclose(p);
            return (*bus > 0 && *dev > 0) ? 0 : -1;
        }
    }
    pclose(p);
    return -1;
}

typedef struct Urb
{
    struct usbdevfs_urb* u;
    uint8_t* buf;
    int pkts;
    int is_fb;
} Urb;

static Urb* alloc_urb(int ep, int pkts, int pkt_cap, int is_fb)
{
    Urb* x = calloc(1, sizeof *x);
    x->u = calloc(1, sizeof(struct usbdevfs_urb) + pkts * sizeof(struct usbdevfs_iso_packet_desc));
    x->buf = calloc(1, (size_t)pkts * pkt_cap);
    x->pkts = pkts;
    x->is_fb = is_fb;
    x->u->type = USBDEVFS_URB_TYPE_ISO;
    x->u->endpoint = ep;
    x->u->flags = USBDEVFS_URB_ISO_ASAP;
    x->u->buffer = x->buf;
    x->u->number_of_packets = pkts;
    x->u->usercontext = x;
    return x;
}

static uint32_t fb_value = NOMINAL_FB;
static uint32_t phase = 0;
static double sine_phase = 0;

static void fill_out(Urb* x)
{
    int off = 0;
    for (int i = 0; i < x->pkts; i++)
    {
        phase += fb_value;
        int frames = phase >> 16;
        phase &= 0xffff;
        if (frames > MAX_PKT_FRAMES)
            frames = MAX_PKT_FRAMES;
        int16_t* s = (int16_t*)(x->buf + off);
        for (int f = 0; f < frames; f++)
        {
            int16_t v = (int16_t)(sin(sine_phase) * 12000);
            sine_phase += 2 * M_PI * 440.0 / RATE;
            if (sine_phase > 2 * M_PI)
                sine_phase -= 2 * M_PI;
            *s++ = v;
            *s++ = v;
        }
        x->u->iso_frame_desc[i].length = frames * 4;
        x->u->iso_frame_desc[i].actual_length = 0;
        x->u->iso_frame_desc[i].status = 0;
        off += frames * 4;
    }
    x->u->buffer_length = off;
}

static void fill_fb(Urb* x)
{
    for (int i = 0; i < x->pkts; i++)
    {
        x->u->iso_frame_desc[i].length = 4;
        x->u->iso_frame_desc[i].actual_length = 0;
        x->u->iso_frame_desc[i].status = 0;
    }
    x->u->buffer_length = x->pkts * 4;
}

static int submit(Urb* x)
{
    return ioctl(fd, USBDEVFS_SUBMITURB, x->u);
}

int main(int argc, char** argv)
{
    int seconds = 10, use_fb = 1, nurbs = 16, pkts = 8;
    for (int i = 1; i < argc; i++)
    {
        if (!strcmp(argv[i], "--nofeedback"))
            use_fb = 0;
        else if (!strcmp(argv[i], "--urbs") && i + 1 < argc)
            nurbs = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--pkts") && i + 1 < argc)
            pkts = atoi(argv[++i]);
        else
            seconds = atoi(argv[i]);
    }

    int bus, dev;
    if (find_device(&bus, &dev))
    {
        fprintf(stderr, "Tracker+ (16d0:1119) not found\n");
        return 1;
    }
    char path[64];
    snprintf(path, sizeof path, "/dev/bus/usb/%03d/%03d", bus, dev);
    fd = open(path, O_RDWR);
    if (fd < 0)
    {
        fprintf(stderr, "open %s: %s (need root)\n", path, strerror(errno));
        return 1;
    }
    printf("device %s, %d URBs x %d packets, feedback %s, %d s\n",
           path, nurbs, pkts, use_fb ? "on" : "off (nominal 44.1k)", seconds);

    struct usbdevfs_disconnect_claim dc = { .interface = IFACE };
    strncpy(dc.driver, "snd-usb-audio", sizeof dc.driver - 1);
    dc.flags = 0;
    if (ioctl(fd, USBDEVFS_DISCONNECT_CLAIM, &dc) < 0)
    {
        perror("DISCONNECT_CLAIM");
        return 1;
    }
    struct usbdevfs_setinterface si = { .interface = IFACE, .altsetting = ALT };
    if (ioctl(fd, USBDEVFS_SETINTERFACE, &si) < 0)
    {
        perror("SETINTERFACE");
        return 1;
    }

    Urb* outs[64];
    if (nurbs > 64)
        nurbs = 64;
    for (int i = 0; i < nurbs; i++)
    {
        outs[i] = alloc_urb(EP_OUT, pkts, MAX_PKT_FRAMES * 4, 0);
        fill_out(outs[i]);
        if (submit(outs[i]) < 0)
        {
            perror("submit OUT");
            return 1;
        }
    }
    Urb* fbs[4];
    int nfb = use_fb ? 4 : 0;
    for (int i = 0; i < nfb; i++)
    {
        fbs[i] = alloc_urb(EP_FB, FB_PKTS, 4, 1);
        fill_fb(fbs[i]);
        if (submit(fbs[i]) < 0)
        {
            perror("submit FB");
            return 1;
        }
    }

    double t0 = now(), tlast = t0;
    long pk_ok = 0, pk_err = 0, frames = 0, gaps = 0, gap_uframes = 0;
    long w_pk = 0, w_frames = 0, w_gaps = 0;
    int have_start = 0;
    unsigned expect_start = 0;
    unsigned first_errno_status = 0;
    int first_err_seen = 0;

    while (now() - t0 < seconds)
    {
        struct usbdevfs_urb* done = NULL;
        if (ioctl(fd, USBDEVFS_REAPURB, &done) < 0)
        {
            if (errno == EINTR)
                continue;
            perror("REAPURB");
            break;
        }
        Urb* x = done->usercontext;
        if (x->is_fb)
        {
            int off = 0;
            for (int i = 0; i < x->pkts; i++)
            {
                if (done->iso_frame_desc[i].actual_length == 4)
                {
                    uint32_t v;
                    memcpy(&v, x->buf + i * 4, 4);
                    if (v > NOMINAL_FB / 2 && v < NOMINAL_FB * 2)
                        fb_value = v;
                }
                off += 4;
            }
            (void)off;
            fill_fb(x);
            submit(x);
            continue;
        }
        unsigned start = (unsigned)done->start_frame;
        if (have_start)
        {
            unsigned d = (start - expect_start) & 0x3fff;
            if (d != 0 && d < 0x2000)
            {
                gaps++;
                w_gaps++;
                gap_uframes += d;
            }
        }
        expect_start = start + x->pkts;
        have_start = 1;
        for (int i = 0; i < x->pkts; i++)
        {
            if (done->iso_frame_desc[i].status == 0)
            {
                pk_ok++;
                w_pk++;
                frames += done->iso_frame_desc[i].length / 4;
                w_frames += done->iso_frame_desc[i].length / 4;
            }
            else
            {
                pk_err++;
                if (!first_err_seen)
                {
                    first_err_seen = 1;
                    first_errno_status = (unsigned)-done->iso_frame_desc[i].status;
                }
            }
        }
        fill_out(x);
        if (submit(x) < 0)
        {
            perror("resubmit OUT");
            break;
        }
        double t = now();
        if (t - tlast >= 1.0)
        {
            printf("t=%4.1fs pkts/s=%6.0f frames/s=%6.0f gaps=%ld fb=%.0f Hz\n",
                   t - t0, w_pk / (t - tlast), w_frames / (t - tlast), w_gaps,
                   fb_value / 65536.0 * 8000.0);
            w_pk = w_frames = w_gaps = 0;
            tlast = t;
        }
    }

    double el = now() - t0;
    printf("\nTOTAL %.1fs: packets_ok=%ld (%.0f/s, expect 8000)  frames=%ld (%.0f/s, expect ~%d)\n",
           el, pk_ok, pk_ok / el, frames, frames / el, RATE);
    printf("      packet_errors=%ld (first errno %u)  gaps=%ld  skipped_uframes=%ld\n",
           pk_err, first_errno_status, gaps, gap_uframes);
    printf("VERDICT: %s\n",
           (pk_ok / el > 7600 && gaps == 0)
             ? "xHCI + device sustain 125us OUT cadence -> fault is in snd-usb-audio/ALSA path"
             : "wire-level drops reproduced without snd-usb-audio -> xHCI/controller/device-descriptor path");

    for (int i = 0; i < nurbs; i++)
        ioctl(fd, USBDEVFS_DISCARDURB, outs[i]->u);
    for (int i = 0; i < nfb; i++)
        ioctl(fd, USBDEVFS_DISCARDURB, fbs[i]->u);
    for (int i = 0; i < nurbs + nfb; i++)
    {
        struct usbdevfs_urb* d;
        if (ioctl(fd, USBDEVFS_REAPURBNDELAY, &d) < 0)
            break;
    }
    si.altsetting = 0;
    ioctl(fd, USBDEVFS_SETINTERFACE, &si);
    unsigned ifn = IFACE;
    ioctl(fd, USBDEVFS_RELEASEINTERFACE, &ifn);
    struct usbdevfs_ioctl cn = { .ifno = IFACE, .ioctl_code = USBDEVFS_CONNECT, .data = NULL };
    ioctl(fd, USBDEVFS_IOCTL, &cn);
    close(fd);
    return 0;
}
