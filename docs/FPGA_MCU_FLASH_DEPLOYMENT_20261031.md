# R6 areaopt4 + MCU r18 联合 Flash 部署记录

记录日期：2026-10-31（北京时间）
目标器件：Anlogic PH1P35MDG324
烧录工具：FutureDynasty 官方命令行
部署状态：外部 SPI Flash 写入与厂商页校验通过；冷启动待验证

## 部署结果

FutureDynasty 连接确认目标为 PH1P35MDG324，检测到 SPI Flash ID 0xC8。联合镜像大小为 14,775,152 字节，Flash 容量为 16,777,216 字节。命令行返回码为 0，并报告 SPI flash Page program and verify 与 R6_AREAOPT4_R18_FLASH_PROGRAM_VERIFY_COMPLETE。

| 产物 | 文件 | 大小 | SHA-256 |
| --- | --- | ---: | --- |
| FPGA bitstream | [firmware/camera_system_fpga.bit](../firmware/camera_system_fpga.bit) | 1,789,536 B | 07521eae26c34b68ff50bd15f76fc7fd362dbfee2a39dc9a3543b95187a92ed4 |
| FPGA + MCU 联合 Flash | [firmware/camera_system_flash.bit](../firmware/camera_system_flash.bit) | 14,775,152 B | a8d67ccbd731a3e29d6dc075faf06dfb548774e9fedae09505a914512facb9c3 |
| MCU ELF | [firmware/mcu_app.elf](../firmware/mcu_app.elf) | 256,632 B | 5a51dd100ab7b56b18160908cc044564db5fe6431b06780c255d44fc93b6bc15 |
| MCU BIN | [firmware/mcu_app.bin](../firmware/mcu_app.bin) | 29,120 B | 0da7b295609b3b76ab24e55b00b338cb7b8bf4a78ff6d6673cf68583ece87eac |
| MCU 启动载荷 | [firmware/boot/payload.bin](../firmware/boot/payload.bin) | 29,152 B | 287f33ea34178bf25ceac46631201e36c4ea6f574172eb68d990e0d641a58421 |

启动程序位于 0xE00000，MCU payload 位于 0xE10000。MCU target-os r18 构建载荷版本为 95。MCU 应用启动后搬运至 TCM；本次仅确认镜像已写入并通过 Flash 页校验，掉电后的启动加载和运行状态尚未实测。

## FPGA 资源与时序

R6 areaopt4 Routed 结果：

| 项目 | 结果 |
| --- | ---: |
| Slice | 20,091 / 21,216 |
| ERAM | 103 / 108 |
| DSP | 30 / 40 |
| SWNS / HWNS | +0.132 ns / +0.020 ns |
| STNS / HTNS | 0 / 0 |

资源相对 v116 基线增加 94 Slice，减少 5 ERAM 和 1 DSP。目标预算按用户接受的 20,091 Slice 上限记录。

MCU 内存统计：text 28,876 B、data 240 B、bss 16,572 B，另预留 2,048 B 栈；合计 47,736 / 49,152 B，余量 1,416 B。

## 当前功能验收边界

17 段视频套件仍未全部通过，已知问题包括：

- 倾斜的数字 3 误识为 2。
- 手机数字 0 和部分远距离数字漏检。
- 倾斜场景下 ArUco 漏检。

本次 Flash 写入期间未回放视频，未发送 UART 或电机命令，也未进行断电冷启动。因此，页校验、Routed 时序及资源数字不能作为全视频通过或冷启动成功的证据。完整历史回归记录见 [VIDEO_SUITE_VALIDATION_20261029.md](VIDEO_SUITE_VALIDATION_20261029.md)。

## R6 形状候选源码

R6 bitstream 构建使用的 ua_track_detect.v SHA-256 为：

37d9271bbdbd5bdd5089341d6cf90ba45b76e431958072ecf50c85cfd84682b1

精确候选副本保存在 [verification/candidates/r6_areaopt4_20261031/ua_track_detect.v](../verification/candidates/r6_areaopt4_20261031/ua_track_detect.v)。该文件作为独立候选存档，没有替换维护 RTL；17 段视频未全部通过前，不应将它描述为已验收算法。当前发布 bitstream 与简单地从维护分支重建的结果不保证一致。

## 日志与清单

- [verification/release_evidence.json](../verification/release_evidence.json)：设备、镜像哈希、资源、时序及未完成的验收项。
- [verification/native_flash_program.log](../verification/native_flash_program.log)：FutureDynasty 命令行写入与页校验日志副本。
- [PACKAGE_MANIFEST.json](../PACKAGE_MANIFEST.json)：仓库交付文件 SHA-256 清单。
