# Multi Fir Filter

    开发板： ALINX7035B 开发板（XILINX xc7a35tfgg484-2）
    ADC：   ALINX：AN9238（AD9238）
    DAC：   ALINX：AN9767（AD9767）

## 模块描述

| `adc_ad9238` | -> | `fir_filter` | -> | `dac_format` | -> | `dac_ad9767` |

旁路：| `adc_ad9238` | -> | `fft_core` | -> | `uart_fft_sender` | -> | `uart_tx` |


## 工程结构

Vivado 默认生成的工程

你可以记住的路径：

| 路径                                               | 描述    |
|---------------------------------------------------|---------|
| `multi_fir_filter.srcs\sources_1\new\`            | 源文件   |
| `multi_fir_filter.srcs\constrs_1\new\ax7035b.xdc` | 约束文件 |

关键模块路径：

| 路径                                                | 描述                   |
|----------------------------------------------------|------------------------|
| `multi_fir_filter.srcs\sources_1\new\top.v`        | 顶层模块                 |
| `multi_fir_filter.srcs\sources_1\new\adc_ad9238.v` | ad9238驱动              |
| `multi_fir_filter.srcs\sources_1\new\dac_ad9767.v` | ad9767驱动              |
| `multi_fir_filter.srcs\sources_1\new\dac_format.v` | 格式转换：12bit -> 14bit |
| `multi_fir_filter.srcs\sources_1\new\fir_filter.v` | FIR滤波器               |
| `multi_fir_filter.srcs\sources_1\new\fft_core.v`   | FFT频谱分析（Xilinx FFT IP） |
| `multi_fir_filter.srcs\sources_1\new\uart_fft_sender.v` | FFT结果UART发送（FireWater格式） |
| `multi_fir_filter.srcs\sources_1\new\uart_tx.v`    | UART串口发送            |


## 代码风格

- 简洁明了，使用中文详细注释
- 模块功能简单，可复用性强
- 变量风格采用 snake_case

## 准则

- 自行判断是否使用 vivado 的 ip 核，使用 ip 核时应告诉我核心配置和配置完后的 Summary 供我检查


## 验证与调试

不用验证，由我自行上板验证




