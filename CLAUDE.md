# Multi Fir Filter

    开发板： ALINX7035B 开发板（XILINX xc7a35tfgg484-2）
    ADC：   ALINX：AN9238（AD9238）
    DAC：   ALINX：AN9767（AD9767）

## 模块描述

| `adc_ad9238` | -> ... -> | `dac_format` | -> | `dac_ad9767` |


## 工程结构

Vivado 默认生成的工程

你可以记住的路径：

| 路径                                               | 描述    |
|---------------------------------------------------|---------|
| `multi_fir_filter.srcs\sources_1\new\`            | 源文件   |
| `multi_fir_filter.srcs\constrs_1\new\ax7035b.xdc` | 约束文件 |

## 代码风格

- 简洁明了，使用中文详细注释
- 模块功能简单，可复用性强
- 变量风格采用 snake_case

## 准则

- 自行判断是否使用 vivado 的 ip 核


## 验证与调试

不用验证，由我自行上板验证




