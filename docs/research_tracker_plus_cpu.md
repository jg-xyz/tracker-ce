# Research: Tracker+ CPU (NXP i.MX RT1051)

Sources: this repo (`platforms/imx/`) plus distributor/Keil listings found by web search.
The NXP datasheet itself was **not** retrieved; datasheet-level claims below are marked.

## Part

| Item | Value | Source |
|---|---|---|
| SoC | NXP i.MX RT1051, part `MIMXRT1051CVL5B` | `board/pin_mux.c`, `board/clock_config.c` (`package_id: MIMXRT1051CVL5B`), build flag `-DCPU_MIMXRT1051CVL5B` in the `mise run build:plus` output |
| Family | i.MX RT1050 "crossover" MCU, datasheet "i.MX RT1050 Crossover Processors for Industrial Products" | [Digi-Key listing](https://www.digikey.com.br/en/products/detail/nxp-usa-inc/MIMXRT1051CVL5B/8344040), [NXP part page](https://www.nxp.com/part/MIMXRT1051CVJ5B) |
| Core | single Arm Cortex-M7 | build flag `-mcpu=cortex-m7` |
| Package | 196-ball MAPBGA, 10 x 10 mm, 0.65 mm pitch (`VL` suffix) | search results, unverified against datasheet |
| On-chip RAM | 512 KB, split as TCM and on-chip SRAM | [Keil device page](https://keil.arm.com/devices/nxp-mimxrt1051cvl5b); firmware linker regions below |

## Clock speed: firmware runs at 528 MHz, not 600 MHz

Distributor listings disagree (528 MHz vs 600 MHz); Keil lists 600 MHz. The silicon
grade may allow 600 MHz, but **this firmware configures 528 MHz**
(`platforms/imx/board/clock_config.c`):

* ARM PLL `loopDivider = 88` -> 24 MHz x 88 / 2 = 1056 MHz.
* `CLOCK_SetDiv(kCLOCK_ArmDiv, 1)` divides by 2 -> `AHB_CLK_ROOT` = **528 MHz** (the
  generated header comment states `AHB_CLK_ROOT.outFreq 528 MHz`).
* Derived: IPG 132 MHz, SEMC (SDRAM) 132 MHz, SDHC1/2 198 MHz, FlexSPI 66 MHz,
  USB PHY 480 MHz, SAI1 MCLK 11.2896 MHz (44.1 kHz audio family).
* `SystemCoreClock` is used for SysTick and a DWT cycle counter
  (`platforms/imx/source/TimeControl.cpp`), so timing code follows the real clock.

Going to 600 MHz would mean changing the ARM PLL/divider and, per NXP convention,
the core voltage (DCDC); that was not checked and is not something to try without the
datasheet limits for this exact grade (the `5B` suffix is assumed, not confirmed, to be
the 600 MHz grade).

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
* Firmware is compiled `-mfpu=fpv5-sp-d16 -mfloat-abi=hard`: single-precision hardware
  FPU; double precision would be software. (Whether the RT1050 M7 FPU also supports
  double is a datasheet question not checked here.)

## Relevance

* Audio and the 28-channel USB audio device share this one core with the UI and SD
  I/O; the SDRAM bus (132 MHz x 16 bit) is the likely bandwidth limit for sample
  playback, not the 528 MHz core. Unmeasured.
* CPU headroom while recording and playing together is an open question in
  [record with playback](research_record_with_playback.md); the DWT counter and
  `Profiler.cpp` in `core/source/` are the existing tools to measure it.

## Open items

* Fetch the NXP datasheet and confirm: max frequency per grade, FPU, package.
* Confirm whether 600 MHz is supported on this exact part and what DCDC setting it needs.
