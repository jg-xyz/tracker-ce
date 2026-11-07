# Research: Tracker+ CPU (NXP i.MX RT1051)

Sources: this repo (`platforms/imx/`), distributor/Keil listings, and the NXP datasheet
*i.MX RT1050 Crossover Processors for Consumer Products*, IMXRT1050CEC **Rev. 1.1,
08/2018** (read via the [Farnell mirror](https://www.farnell.com/datasheets/2674658.pdf);
nxp.com's direct PDF URL returned 404 to a script). Caveat: that datasheet covers
**D (consumer, 0-95 C)** parts only. Our part is **C (industrial)**, covered by the
separate industrial datasheet (IMXRT1050IEC), which was not retrieved. Numbers cited
as "datasheet" below are from the consumer document and may differ for the industrial one.

## Part

| Item | Value | Source |
|---|---|---|
| SoC | NXP i.MX RT1051, part `MIMXRT1051CVL5B` | `board/pin_mux.c`, `board/clock_config.c` (`package_id: MIMXRT1051CVL5B`), build flag `-DCPU_MIMXRT1051CVL5B` in the `mise run build:plus` output |
| Family | i.MX RT1050 "crossover" MCU, datasheet "i.MX RT1050 Crossover Processors for Industrial Products" | [Digi-Key listing](https://www.digikey.com.br/en/products/detail/nxp-usa-inc/MIMXRT1051CVL5B/8344040), [NXP part page](https://www.nxp.com/part/MIMXRT1051CVJ5B) |
| Core | single Arm Cortex-M7 | build flag `-mcpu=cortex-m7` |
| Package | 196-ball MAPBGA, 10 x 10 mm, 0.65 mm pitch (`VL` suffix) | search results, unverified against datasheet |
| On-chip RAM | 512 KB, split as TCM and on-chip SRAM | [Keil device page](https://keil.arm.com/devices/nxp-mimxrt1051cvl5b); firmware linker regions below |

## Part number decode (datasheet Figure 1)

`MIMXRT1051CVL5B` = **M** mass production, **RT** i.MX RT, **1** first-gen family,
**05** RT1050 sub-family, **1** tier 1 = *reduced feature* (RT1052 is the full-feature
tier), **C** industrial -40..+105 C, **VL** 196-pin MAPBGA 10 x 10 mm 0.65 mm pitch,
**5** = **500 MHz** speed grade, **B** = silicon rev A1. So the `5` in the part is the
500 MHz grade, not 600 (the `6` parts are the 600 MHz ones). The listings that say
528 MHz match the datasheet's 528 MHz operating point below.

## Datasheet facts

* Single Cortex-M7 with 32 KB L1 I-cache and 32 KB L1 D-cache, MPU (16 regions), FPU
  "full featured, VFPv5", up to 512 KB I-TCM+D-TCM in total.
* 512 KB on-chip RAM, configurable (FlexRAM) and shared with the TCM; boot ROM 96 KB.
* External memory: 8/16-bit SDRAM up to SDRAM-166, QSPI flash with XIP, SD/eMMC.
* Operating ranges (Table 10, `VDD_SOC_IN`): core at **528 MHz needs 1.15-1.3 V**;
  **600 MHz is the "Overdrive" point, 1.25-1.3 V**; 132 MHz 1.15 V; 24 MHz 0.925 V.
  DCDC input 2.8-3.6 V.

## Clock speed: firmware runs at 528 MHz

The firmware configures 528 MHz, the datasheet's standard run point
(`platforms/imx/board/clock_config.c`):

* ARM PLL `loopDivider = 88` -> 24 MHz x 88 / 2 = 1056 MHz.
* `CLOCK_SetDiv(kCLOCK_ArmDiv, 1)` divides by 2 -> `AHB_CLK_ROOT` = **528 MHz** (the
  generated header comment states `AHB_CLK_ROOT.outFreq 528 MHz`).
* Derived: IPG 132 MHz, SEMC (SDRAM) 132 MHz, SDHC1/2 198 MHz, FlexSPI 66 MHz,
  USB PHY 480 MHz, SAI1 MCLK 11.2896 MHz (44.1 kHz audio family).
* `SystemCoreClock` is used for SysTick and a DWT cycle counter
  (`platforms/imx/source/TimeControl.cpp`), so timing code follows the real clock.

600 MHz would be the datasheet's Overdrive point (higher `VDD_SOC_IN`, more heat) and
is the `6` speed grade; this part is the `5` grade, so it is not a supported target.
Also note the 528 MHz setting already sits above the nominal 500 MHz grade label; the
datasheet's 528 MHz operating point suggests that is by design, but the industrial
datasheet should be checked.

## Memory map used by the firmware

`platforms/imx/linker/TrackerPlus/*.ld`:

| Region | Origin | Size | Use |
|---|---|---|---|
| `QSPI_FLASH` | `0x60030000` | ~16.2 MB | code, XIP via FlexSPI (build reports 10% used) |
| `SRAM_DTC` | `0x20000000` | 384 KB (352 KB reported by linker) | data + stack |
| `SRAM_ITC` | `0x8` | ~96 KB | hot code |
| `SRAM_OC` | `0x20200000` | 32 KB | on-chip SRAM |
| `EXTERNAL_RAM` | `0x80000000` | 64 MB | SDRAM on SEMC, 16-bit bus (`board/peripherals.c`: `memsize_kbytes = 65536`, `kSEMC_PortSize16Bit`) |

Last build (`mise run build:plus`): `SRAM_DTC` 93.96%, `SRAM_ITC` 82.65%, `SRAM_OC`
70.84%, `EXTERNAL_RAM` 99.99% used. RAM is nearly full, which matters for any feature
that needs more buffers (see [record with playback](research_record_with_playback.md)).

## Caches and FPU

* I- and D-cache are enabled at boot (`board/board.c`: `SCB_EnableDCache()` /
  `SCB_EnableICache()`).
* Datasheet: 32 KB I-cache + 32 KB D-cache; FPU is VFPv5 (the datasheet text does not say
  single or double precision).
* Firmware is compiled `-mfpu=fpv5-sp-d16 -mfloat-abi=hard`: single-precision hardware
  instructions only, so any `double` math is software emulated.

## Relevance

* Audio and the 28-channel USB audio device share this one core with the UI and SD
  I/O; the SDRAM bus (132 MHz x 16 bit) is the likely bandwidth limit for sample
  playback, not the 528 MHz core. Unmeasured.
* CPU headroom while recording and playing together is an open question in
  [record with playback](research_record_with_playback.md); the DWT counter and
  `Profiler.cpp` in `core/source/` are the existing tools to measure it.

## Open items

* Fetch the industrial datasheet (IMXRT1050IEC) and re-check Table 10 and the 500 MHz
  grade vs 528 MHz firmware setting.
* Rev. 1.1 (2018) is old; check for a newer revision and the errata.
* Whether the M7 FPU is double-capable (reference manual / Arm M7 TRM).
