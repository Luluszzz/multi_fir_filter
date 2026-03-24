# Multi FIR Filter — FPGA 实时信号处理系统

**[English](README_en.md) | 中文**

![FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7-blue)
![Language](https://img.shields.io/badge/Language-Verilog-orange)
![Board](https://img.shields.io/badge/Board-ALINX%20AX7035B-green)
![Status](https://img.shields.io/badge/Status-Verified-brightgreen)

基于 **Xilinx Artix-7 (XC7A35T)** 的实时 ADC 采集 → FIR 数字滤波 → DAC 输出系统，附带 FFT 频谱分析与 UART 上报功能。

## 系统架构

```
Main Path:

  Analog In --> [adc_ad9238] --> [fir_filter] --> [dac_format] --> [dac_ad9767] --> Analog Out
                 12bit ADC       Low-Pass         12->14bit        14bit DAC

Bypass Path:

  adc_ad9238 --> [fft_core] --> [uart_fft_sender] --> [uart_tx] --> PC Serial
                  1024-FFT       FireWater ASCII      115200 baud
```

## 硬件平台

| 组件 | 型号 | 说明 |
|------|------|------|
| 开发板 | ALINX AX7035B | Xilinx XC7A35TFGG484-2 |
| ADC 模块 | ALINX AN9238 | AD9238，双通道 12bit，最高 65MSPS |
| DAC 模块 | ALINX AN9767 | AD9767，双通道 14bit，最高 125MSPS |

## 功能特性

- **实时 FIR 滤波**：基于 Xilinx FIR Compiler IP 核，可通过 COE 文件灵活配置滤波器系数
- **FFT 频谱分析**：1024 点 FFT，Radix-4 架构，自然序输出
- **幅值估算**：采用 Alpha-Max-Beta-Min 近似算法，无需额外 DSP 资源（最大误差 ≈ 11.8%）
- **串口上报**：FireWater 协议格式输出频谱数据，可直接用上位机可视化
- **时钟净化**：MMCME2_BASE 原语进行时钟管理，确保信号完整性
- **采样率**：约 1.024 MHz（50 MHz 系统时钟分频）

## 模块说明

| 模块 | 文件 | 功能 | 关键参数 |
|------|------|------|----------|
| `top` | `top.v` | 顶层模块，时钟管理与数据通路连接 | SYS_CLK=50MHz, SAMPLE_RATE=1.024MHz |
| `adc_ad9238` | `adc_ad9238.v` | AD9238 驱动，ODDR 时钟输出 + 采样选通 | 12bit, Offset Binary |
| `fir_filter` | `fir_filter.v` | FIR 低通滤波器封装（Offset Binary ↔ 补码转换） | 输入 12bit → IP 16bit → 输出 12bit |
| `dac_format` | `dac_format.v` | 数据位宽转换，高位对齐补零 | 12bit → 14bit |
| `dac_ad9767` | `dac_ad9767.v` | AD9767 驱动，双 ODDR 输出时钟与写信号 | 14bit |
| `fft_core` | `fft_core.v` | FFT 频谱分析，状态机控制采集→变换→存储 | 1024点, Radix-4, Unscaled |
| `uart_fft_sender` | `uart_fft_sender.v` | FFT 结果格式化发送（Double-Dabble BCD 转换） | FireWater ASCII 协议 |
| `uart_tx` | `uart_tx.v` | UART 串口发送 | 115200 baud, 8N1 |

## 关键技术细节

### FIR 滤波器

- **IP 核**：Xilinx FIR Compiler (`fir_compiler_0`)
- **系数文件**：`matlab/fir_lpf_125k_275k_2m.coe`（低通，通带 125kHz，阻带 275kHz，采样率 2MHz）
- **数据流**：输入 Offset Binary → 反转 MSB 转补码 → 符号扩展至 16bit → IP 核处理 → 截取高 12bit → 反转 MSB 回 Offset Binary

### FFT 频谱分析

- **IP 核**：Xilinx FFT (`xfft_0`)
- **配置**：1024 点 / Radix-4 Burst I/O / 定点 / 相位因子 16bit / Unscaled / 自然序输出
- **状态机**：`IDLE → CONFIG → COLLECT(1024样本) → WAIT → STORE → DONE`
- **幅值计算**：`mag ≈ max(|Re|, |Im|) + min(|Re|, |Im|) / 4`（Alpha-Max-Beta-Min）

### UART 上报协议

串口输出 FireWater 兼容的 ASCII 格式，可直接对接上位机软件：

```
channels: 0,12345\n
channels: 1,23456\n
...
channels: 1023,34567\n
```

## 工程结构

```
multi_fir_filter/
├── multi_fir_filter.srcs/
│   ├── sources_1/new/              # RTL 源文件
│   │   ├── top.v                   # 顶层模块
│   │   ├── adc_ad9238.v            # ADC 驱动
│   │   ├── dac_ad9767.v            # DAC 驱动
│   │   ├── dac_format.v            # 格式转换
│   │   ├── fir_filter.v            # FIR 滤波器
│   │   ├── fft_core.v              # FFT 核心
│   │   ├── uart_fft_sender.v       # FFT 结果发送
│   │   └── uart_tx.v               # UART 发送
│   └── constrs_1/new/
│       └── ax7035b.xdc             # 引脚约束
├── multi_fir_filter.cache/         # Vivado 缓存
├── multi_fir_filter.gen/           # IP 核生成文件
└── multi_fir_filter.ip_user_files/ # IP 核用户文件
```

## IP 核

工程已包含所有 IP 核配置文件（`.xci`），克隆后 Vivado 会自动识别，**无需手动创建**。

> 以下仅为参考，便于理解设计参数。

### FIR Compiler (`fir_compiler_0`)

| 参数 | 值 |
|------|-----|
| Filter Type | Single Rate |
| Coefficient Source | COE File (`matlab/fir_lpf_125k_275k_2m.coe`) |
| Input Data Width | 12 |
| Coefficient Width | 16 |
| Output Width | 30 |

### FFT (`xfft_0`)

| 参数 | 值 |
|------|-----|
| Transform Length | 1024 |
| Architecture | Radix-4, Burst I/O |
| Data Format | Fixed Point |
| Input Data Width | 12 |
| Phase Factor Width | 16 |
| Scaling | Unscaled |
| Output Ordering | Natural Order |

> Block RAM 通过 `reg` 数组推断，未使用额外 IP 核。

## 引脚分配

| 信号 | FPGA 引脚 | 电平标准 | 说明 |
|------|-----------|---------|------|
| `sys_clk` | Y18 | LVCMOS33 | 50MHz 系统时钟 |
| `sys_rst_n` | F20 | LVCMOS33 | 复位按键 |
| `ad9238_data_ch0[11:0]` | B16–D17 | LVCMOS33 | ADC 数据（J9） |
| `ad9238_clk_ch0` | D19 | LVCMOS33 | ADC 采样时钟 |
| `ad9767_data_ch0[13:0]` | P17–W21 | LVCMOS33 | DAC 数据（J10） |
| `ad9767_clk_ch0` | Y21 | LVCMOS33 | DAC 时钟（FAST） |
| `ad9767_wrt_ch0` | Y22 | LVCMOS33 | DAC 写信号 |
| `uart_tx` | G16 | LVCMOS33 | UART 发送 |

## 快速开始

> 要求：Vivado 2025.2（其他版本可能需要升级 IP）

```bash
git clone https://github.com/Luluszzz/multi_fir_filter.git
```

1. 打开 Vivado → **Open Project** → 选择 `multi_fir_filter.xpr`
2. Vivado 会自动加载 IP 核（`fir_compiler_0`、`xfft_0`），如提示 IP 锁定则右键 **Upgrade IP**
3. 点击 **Generate Bitstream**（Vivado 自动完成综合 → 实现 → 生成比特流）
4. **Open Hardware Manager** → 下载至开发板
