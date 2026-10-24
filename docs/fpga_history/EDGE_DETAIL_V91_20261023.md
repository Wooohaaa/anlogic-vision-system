# v91：增加弱边缘与卡通描边

基线：v89 FPGA＋v83 MCU；MCU、摄像头、AWB/AE、检测器、OSD及引脚不改。

## 变更

- 维护RTL新增 EDGE_DETAIL_ENABLE，默认关闭，生产isp实例开启。沿用原来暗部的x2幅值通路，扩展到正常亮度，不额外增加行缓存或流水级。
- 原始归一化梯度小于4 DN不增强；其余幅值x2并饱和至255，不溢出回绕；暗部不会重复乘两次。
- 卡通弱边缘门槛由16降到8，仍要求前一或前二个4像素组有弱边缘支持；强边缘门槛24降到16，可独立通过。
- 不移动描边空间位置，不修改颜色量化、不扩大黑线宽度、不修改顶部2像素黑边。
- Sobel模式是强度图，没有独立二值阈值，因此通过提高有效梯度强度改善可见性，而不是虚称降低了Sobel二值阈值。

## 验证与限制

`tools/test_edge_detail_v91.py`覆盖16组RTL测试：1280像素行宽、连续及带气泡输入、明暗输入、新旧配置、直通/灰度/边缘/二值/素描/浮雕与独立卡通参考。卡通额外包含弱对比纹理与2 DN平坦微扰，比较新旧边缘数量。

首次回归16组通过；构建入口会重新运行并冻结最终输入哈希，以最终 `tmp/v91_regression/result.json` 为准。固定流水与行首行尾同步由参考队列核对。

这是保留更多边缘的敏感度调整，不是提高图像原始分辨率。4像素组平均和既有平滑仍会丢失部分细节；暗场纹理与噪声可能同时增加，需要实机观察。合成场景回归不能证明真实摄像头的误边缘率。

## 构建/部署

入口：`python tools/deploy_edge_detail_v91.py`。
入口复用v89流程并将产物/日志隔离为v91；依赖脚本纳入回归哈希。先回归、同步副本、综合布局，再布线、检查最终Routed时序、封装原MCU v83联合Flash镜像，通过后才执行一次原生Flash下载。MCU及电机默认关闭状态不改，不发送电机使能命令。

资源上限保持Slice19518/21216（92%以内），ERAM108、DSP40；不得复用v89资源数作为v91最终结果。

最终结果读取：`tmp/v91_pipeline_result.json`、`tmp/v91_build_result.json`、`tmp/v91_flash_programmed.json`。失败或USB阻断时停止，不自动重写或修改驱动。

## 最终构建与烧录记录

2026-10-23 23:38（北京时间），v91联合Flash完成一次官方BitWriter命令行烧录，目标PH1P35MDG324，Page program and verify通过。未执行电机开启或额外串口命令。Flash写入及校验成功不等同于已确认冷启动和真实画质，需要用户重启后观察。

- 最终Routed资源：Slice19409/21216（91.48%，比v89减少41）、ERAM97/108、DSP32/40。
- 最终Confidence Routed；SWNS +0.114ns，HWNS +0.020ns，STNS/HTNS均0。未变更SDC；既有约束/厂商IP告警边界仍见整体审计文档，不称完整CDC/I/O签核。
- 两次16组回归通过；最终输入哈希、源码清单和FPGA bit SHA在烧录前独立复核通过，烧录后联合镜像与成功receipt的SHA再次一致。
- FPGA bit：`deliverables/camera_hdmi_v91_edge_detail_fpga.bit`，SHA256 `781e0f49207eab79388e71b8458485841753ac42fa3af191e53e37ceef296a31`。
- 联合Flash：`deliverables/camera_hdmi_v91_fpga_mcu_flash.bit`，SHA256 `56d7b329dd8c76d948c25fd5c3864ac851efa51781d0e18a9537c9ad4010c9fe`，包含原MCU v83。
- `tmp/v91_pipeline_result.json`：FLASH_PROGRAMMED_VERIFY_PASS；`tmp/v91_flash_programmed.json`：FLASH_PROGRAMMED_NATIVE_VERIFY_PASS_COLD_BOOT_PENDING。
- 合成弱纹理测试（明场，含固定几何边缘）描边组数416→10592；这是特定测试图的敏感度变化，不是实拍检测率或准确率。

实机重点：MODE2/4弱边缘可见性、MODE6细轮廓增加、低光平坦背景是否出现过量黑色噪声，以及原描边对齐是否保持。未采集v91实机图像，不宣称画质验收完成。
