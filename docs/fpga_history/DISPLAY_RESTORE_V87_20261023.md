# v87：恢复改红线前的颜色链路，仅保留卡通描边对齐及显示灰条

## 用户指定范围

v86r1 实板用户反馈仍偏绿。按本轮明确要求，停止继续调白平衡，恢复改红线前 v83 公共颜色链路；最顶部红线仅用灰色覆盖，不再尝试重建首行。只有卡通描边空间偏移修正保留。

## 实现

- `ua_awb_frame.v` 已逐字恢复为 v83，SHA256 `069d841ec2d62f5d4f22b206d627bb6b210316469b49f38eeeedd67d249b088e`，撤销 v86 的增益/采样范围扩展。
- ISP 取消首行行缓存，原 demosaic RGB/valid/user/last 直接进入 AWB；不再加入两行前视和 EOF 刷新。部署源清单不再包含行修复模块，历史实验文件保留但不进入活动链路。
- 跟框回到旧的 1/4 坐标平滑行为（FAST_TRACK_ENABLE=0）。共享暂存无可观察复位的资源实现保留，但须通过旧行为周期等价测试，不宣称此文件与 v83 字节一致。
- 卡通模式使用已验证的同坐标差分描边；其他 0～5 模式和底色函数不改。
- HDMI 末端把**一行**可见像素覆盖为 RGB `808080`。不裁图、不移动行列，不改视频有效信号、显示尺寸或色调。灰条仅显示覆盖，不消除原解码首行异常，也不改变内部白平衡/颜色/形状统计；内部仍可能观察到首行颜色，这是用户选择掩盖而非重建的边界。
- v83 除 mixer/ISP/track/display-algorithm 外的全部已记录维护 RTL 要求逐项 SHA 一致，包含 RAW、曝光、降噪、传感器配置、手势、ArUco、MCU 和电机逻辑。不新增 MCU 工作，上电默认 OFF，不发送运动命令。

## 验证及部署门限

`tools/test_restore_display_v87.py`：

1. v83 AWB 原始 SHA 及其他未改维护 RTL 验证；ISP 中无首行桥或增强白平衡参数。
2. 实际 mixer、字体和 Logo RAM 功能模型的完整 1280×720 彩色帧：首行 1280 个灰色像素，其他普通画面 RGB 与原干净输出相同；clean tap 不被灰条修改。真实 user/last 标记驱动坐标，不用永远为 0 的伪行尾。
3. 1280×720 连续/气泡卡通阶跃、斜边与右边界测试；原 0～5 模式独立参考边界回归。
4. 跟框旧行为周期等价（含复位），原 AWB bootstrap 与开关回归；原 KEY2/controller 回归仅在所有输入 SHA 未改时引用。

综合布局必须 Slice≤19518（92%）、ERAM≤108、DSP≤40；最终 Routed SWNS/HWNS≥0、STNS/HTNS=0。不放宽时钟或路径约束；若需要，使用已有官方 post-route 物理优化，再重新核验全部时序。全部满足后仅下载一次 FPGA＋未改 v83 MCU 联合 Flash，不启动电机。

## 当前状态

`tmp/v87_pipeline_result.json` 为当前流程状态。现已完成独立首行灰色覆盖整帧测试；其余回归和实现进行中。此文不声明实板颜色已经恢复或灰条/描边已由用户验收。

## 最终实现及烧录阻断

全部本轮回归通过：`tmp/v87_regression/result.json`。实际 mixer 整帧统计为 1280 个灰条像素、910066 个普通画面像素、10254 个原叠加像素；灰条以外普通 RGB 与 clean tap 一致。

最终 Confidence Routed：Slice 19506/21216（91.94%）、ERAM 97/108、DSP 32/40；SWNS=0.121 ns、HWNS=0.020 ns、STNS=0、HTNS=0。未放宽任何时钟/路径约束。

- FPGA：`deliverables/camera_hdmi_v87_color_fpga.bit`，SHA256 `c0f2b60151e8e328f54b83b2a7387d8ffb7ba9749a073b5ad698e1ef263d48e8`。
- 联合 Flash（原 v83 MCU）：`deliverables/camera_hdmi_v87_fpga_mcu_flash.bit`，SHA256 `5399959d84a5bd9e8e791fcb1c7e2ff558b6e76f93cfb26ee8e42d02ea96d737`。
- `tmp/v87_build_result.json` 为 ROUTED_VERIFIED_NOT_PROGRAMMED，`tmp/v87_flash_build_result.json` 为 FLASH_IMAGE_VERIFIED_NOT_PROGRAMMED；独立复核全部冻结输入及两个镜像哈希一致。
- 首次官方命令行烧录连接服务成功，但在 `read_device_id -level 1 -total 2` 返回 `PRG-8000 ERROR: transfer failed`。日志 `tmp/v87_flash_program.log` 无 download、擦除或写入命令，所以**本轮没有修改板上 Flash**；不能报告已经回退。
- 当前 STOPPED_REQUIRES_INSPECTION，需用户保持供电、重插烧录 USB 并关闭 BitWriter 后，再授权单次烧录重试；不重复构建、不无限重试、不启动电机。

## 授权重试后成功

用户重新插拔 USB 并回复“好了”后，运行 `tools/program_ready_v87_retry1.py`，先核对既有镜像、冻结输入、最终 Routed 时序及原首次失败确实未擦写，再仅重试一次 Flash 下载，没有重新构建。

2026-10-23 15:44（北京时间）官方 BitWriter 识别 PH1P35MDG324 成功，SPI Flash Page program and verify 完成，耗时约 102.2 秒，日志 `tmp/v87_flash_retry1_program.log` 有 `V87_FLASH_PROGRAM_VERIFY_COMPLETE`。

成功记录 `tmp/v87_flash_programmed.json`，状态 `FLASH_PROGRAMMED_NATIVE_VERIFY_PASS_COLD_BOOT_PENDING`；联合镜像 SHA256 仍为 `5399959d84a5bd9e8e791fcb1c7e2ff558b6e76f93cfb26ee8e42d02ea96d737`。FPGA 为 v87、MCU 仍为 v83，未发送电机启动或串口运动命令。原阻断记录属于首次尝试，当前已烧录成功，但仍需用户断电重启核验颜色、首行灰条及卡通描边；不能把 Flash 校验当作真实画质验证。
