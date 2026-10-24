# v89 顶部线条弱化

## 改动范围

v88 的中灰首行在暗背景上比较显眼。改为 HDMI 输出四周一致的2像素纯黑细边，与显示器黑色边框融为一体；只覆盖外沿，不缩放、不搬移、无行缓存，不修补采集流。

保持1280×720输出与同步时序，检测坐标不变。直通/算法/OSD/ArUco 在最外2像素均由黑边优先覆盖，其余区域不变。DEBUG_MODE 调试图保持原逻辑。原始像素通路不覆盖，故这是显示掩盖，不是消除前级异常源。

生产RTL只改 `rtl/user/hdmi_mixer_user.v` 的遮罩条件与常量颜色。其余 v88 维护RTL、AWB、手势、边缘算法、MCU v83 和约束均逐文件哈希保持不变，不启电机。

## 验证

`tools/test_black_matte_v89.py` 使用实际mixer、整帧1280×720多种RGB图案，逐像素核验：

- 7984个边框像素纯黑，位置与DE对齐。
- 内部913616像素中，903362个非OSD像素与原图通路逐位相同，10254个OSD像素保留原覆盖。
- 原始图像通路全部像素颜色不变。
- v88 手势/边缘/采样/坏帧恢复仿真证据对应源码仍一致；没有将旧mixer测试当作新遮罩通过证据。

## 最终结果

- Routed Slice 19450/21216（91.68%），ERAM97/108、DSP32/40；符合92%上限。
- SWNS +0.164 ns，HWNS +0.020 ns，STNS/HTNS均0，Confidence Routed；STA覆盖95.35%，约束未改变。
- FPGA SHA256 `0ddc0fd73d37101e1728a86f1c9317321953e83dbc10eb91cd27f5fe5185dada`。
- 联合Flash `deliverables/camera_hdmi_v89_fpga_mcu_flash.bit`，SHA256 `f87c684590442ad0e4f6e68f9ead7b154a2c19f6dcb0deac37acd33367f70df7`。
- 604项冻结输入独立核验一致，最终镜像哈希与打包、烧录receipt匹配。
- 2026-10-23 19:18:28 +08:00，官方BitWriter终端单次SPI Flash下载与校验通过，目标PH1P35MDG324；未启电机、未做串口前后置测试。MCU仍为v83。
- `tmp/v89_flash_programmed.json` 为 `FLASH_PROGRAMMED_NATIVE_VERIFY_PASS_COLD_BOOT_PENDING`。Flash校验通过不代替冷启动/真实观感验证，需重启生效后观察；这是遮盖显示，不是异常源修复。
