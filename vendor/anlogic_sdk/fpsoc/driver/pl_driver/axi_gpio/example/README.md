# GPIO

## 概述

GPIO示例工程演示了GPIO口读写功能和中断功能。

## 硬件设置

## 已知问题

无已知问题

## 运行说明
以下两个示例在运行前需要烧录对应配置的bit文件。

示例1:axi_gpio_output_led.c
- 该示例演示了 GPIO 如何在 rtos 下如何控制 GPIO 的方向和输出。
> Notes：该示例用到了channel 1 Pin 15, channel 2 Pin 14; IP配置需要能够支持这2个channel和pin。

示例2:axi_gpio_input_key.c
- 该示例演示了如何使用 GPIO 的中断。
> Notes：该示例用到了channel 1 Pin 1, channel 2 Pin 1; IP配置需要能够支持该2个channel和pin; 在打开中断后，若改变端口方向，会触发一次中断，所以中断开启后不宜再修改tri寄存器去改变端口方向。
