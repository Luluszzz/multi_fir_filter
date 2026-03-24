# Multi FIR Filter — FPGA Real-Time Signal Processing System

**English | [中文](README.md)**

![FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7-blue)
![Language](https://img.shields.io/badge/Language-Verilog-orange)
![Board](https://img.shields.io/badge/Board-ALINX%20AX7035B-green)
![Status](https://img.shields.io/badge/Status-Verified-brightgreen)

A real-time ADC acquisition → FIR digital filtering → DAC output system based on **Xilinx Artix-7 (XC7A35T)**, with FFT spectrum analysis and UART reporting.

## System Architecture

```
Main Path:

  Analog In --> [adc_ad9238] --> [fir_filter] --> [dac_format] --> [dac_ad9767] --> Analog Out
                 12bit ADC       Low-Pass         12->14bit        14bit DAC

Bypass Path:

  adc_ad9238 --> [fft_core] --> [uart_fft_sender] --> [uart_tx] --> PC Serial
                  1024-FFT       FireWater ASCII      115200 baud
```

## Hardware Platform

| Component | Model | Description |
|-----------|-------|-------------|
| Dev Board | ALINX AX7035B | Xilinx XC7A35TFGG484-2 |
| ADC Module | ALINX AN9238 | AD9238, dual-channel 12-bit, up to 65 MSPS |
| DAC Module | ALINX AN9767 | AD9767, dual-channel 14-bit, up to 125 MSPS |

## Features

- **Real-time FIR Filtering**: Based on Xilinx FIR Compiler IP, filter coefficients configurable via COE file
- **FFT Spectrum Analysis**: 1024-point FFT, Radix-4 architecture, natural order output
- **Magnitude Estimation**: Alpha-Max-Beta-Min approximation, no extra DSP resources needed (max error ≈ 11.8%)
- **Serial Reporting**: FireWater protocol format for spectrum data, directly compatible with PC visualization tools
- **Clock Conditioning**: MMCME2_BASE primitive for clock management, ensuring signal integrity
- **Sample Rate**: ~1.024 MHz (divided from 50 MHz system clock)

## Module Description

| Module | File | Function | Key Parameters |
|--------|------|----------|----------------|
| `top` | `top.v` | Top-level module, clock management & datapath | SYS_CLK=50MHz, SAMPLE_RATE=1.024MHz |
| `adc_ad9238` | `adc_ad9238.v` | AD9238 driver, ODDR clock output + sample strobe | 12bit, Offset Binary |
| `fir_filter` | `fir_filter.v` | FIR low-pass filter wrapper (Offset Binary ↔ two's complement) | Input 12bit → IP 16bit → Output 12bit |
| `dac_format` | `dac_format.v` | Data width conversion, MSB-aligned with zero padding | 12bit → 14bit |
| `dac_ad9767` | `dac_ad9767.v` | AD9767 driver, dual ODDR for clock & write signals | 14bit |
| `fft_core` | `fft_core.v` | FFT spectrum analysis, FSM-controlled collect→transform→store | 1024-pt, Radix-4, Unscaled |
| `uart_fft_sender` | `uart_fft_sender.v` | FFT result formatter & sender (Double-Dabble BCD conversion) | FireWater ASCII protocol |
| `uart_tx` | `uart_tx.v` | UART serial transmitter | 115200 baud, 8N1 |

## Key Technical Details

### FIR Filter

- **IP Core**: Xilinx FIR Compiler (`fir_compiler_0`)
- **Coefficient File**: `matlab/fir_lpf_125k_275k_2m.coe` (low-pass, passband 125 kHz, stopband 275 kHz, sample rate 2 MHz)
- **Data Flow**: Input Offset Binary → invert MSB to two's complement → sign-extend to 16-bit → IP core processing → truncate to upper 12-bit → invert MSB back to Offset Binary

### FFT Spectrum Analysis

- **IP Core**: Xilinx FFT (`xfft_0`)
- **Configuration**: 1024-point / Radix-4 Burst I/O / Fixed Point / Phase Factor 16-bit / Unscaled / Natural Order
- **FSM**: `IDLE → CONFIG → COLLECT (1024 samples) → WAIT → STORE → DONE`
- **Magnitude Calculation**: `mag ≈ max(|Re|, |Im|) + min(|Re|, |Im|) / 4` (Alpha-Max-Beta-Min)

### UART Reporting Protocol

Serial output in FireWater-compatible ASCII format, ready for PC visualization software:

```
channels: 0,12345\n
channels: 1,23456\n
...
channels: 1023,34567\n
```

## Project Structure

```
multi_fir_filter/
├── multi_fir_filter.srcs/
│   ├── sources_1/new/              # RTL source files
│   │   ├── top.v                   # Top-level module
│   │   ├── adc_ad9238.v            # ADC driver
│   │   ├── dac_ad9767.v            # DAC driver
│   │   ├── dac_format.v            # Format converter
│   │   ├── fir_filter.v            # FIR filter
│   │   ├── fft_core.v              # FFT core
│   │   ├── uart_fft_sender.v       # FFT result sender
│   │   └── uart_tx.v               # UART transmitter
│   └── constrs_1/new/
│       └── ax7035b.xdc             # Pin constraints
├── multi_fir_filter.cache/         # Vivado cache
├── multi_fir_filter.gen/           # IP core generated files
└── multi_fir_filter.ip_user_files/ # IP core user files
```

## IP Cores

All IP core configuration files (`.xci`) are included in the repository. Vivado will recognize them automatically after cloning — **no manual IP creation required**.

> The following is for reference only, to help understand the design parameters.

### FIR Compiler (`fir_compiler_0`)

| Parameter | Value |
|-----------|-------|
| Filter Type | Single Rate |
| Coefficient Source | COE File (`matlab/fir_lpf_125k_275k_2m.coe`) |
| Input Data Width | 12 |
| Coefficient Width | 16 |
| Output Width | 30 |

### FFT (`xfft_0`)

| Parameter | Value |
|-----------|-------|
| Transform Length | 1024 |
| Architecture | Radix-4, Burst I/O |
| Data Format | Fixed Point |
| Input Data Width | 12 |
| Phase Factor Width | 16 |
| Scaling | Unscaled |
| Output Ordering | Natural Order |

> Block RAM is inferred from `reg` arrays — no additional IP core used.

## Pin Assignment

| Signal | FPGA Pin | I/O Standard | Description |
|--------|----------|-------------|-------------|
| `sys_clk` | Y18 | LVCMOS33 | 50 MHz system clock |
| `sys_rst_n` | F20 | LVCMOS33 | Reset button |
| `ad9238_data_ch0[11:0]` | B16–D17 | LVCMOS33 | ADC data (J9) |
| `ad9238_clk_ch0` | D19 | LVCMOS33 | ADC sample clock |
| `ad9767_data_ch0[13:0]` | P17–W21 | LVCMOS33 | DAC data (J10) |
| `ad9767_clk_ch0` | Y21 | LVCMOS33 | DAC clock (FAST) |
| `ad9767_wrt_ch0` | Y22 | LVCMOS33 | DAC write signal |
| `uart_tx` | G16 | LVCMOS33 | UART transmit |

## Quick Start

> Requires: Vivado 2025.2 (other versions may require IP upgrade)

```bash
git clone https://github.com/Luluszzz/multi_fir_filter.git
```

1. Open Vivado → **Open Project** → select `multi_fir_filter.xpr`
2. Vivado will auto-load IP cores (`fir_compiler_0`, `xfft_0`). If prompted with IP lock, right-click → **Upgrade IP**
3. Click **Generate Bitstream** (Vivado will automatically run synthesis → implementation → bitstream generation)
4. **Open Hardware Manager** → program the board
