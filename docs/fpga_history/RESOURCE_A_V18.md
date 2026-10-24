# A 方案：保留全部功能的资源优化

## 范围

以 2026-10-13 v17 为基线。保留 1280×720 采集/显示、原 RGB 色值、图像处理模式、自动白平衡、自动曝光、运动/颜色形状/手势/数字识别，以及按键、拨动开关、数码管和 OSD。没有恢复网口，没有更改引脚、PLL、时序例外、识别阈值或图像增强参数。

## 实现

- `osd_char_lib.v`：新增同步读字库，保留原组合读兼容接口。压缩地址后中文和 ASCII 全部保持原字形；新增的读时钟在显示流水第 3 级使用，第 4 级决定字体命中。
- `anlogic_logo_rom.v`：原逐像素 case 改为无损颜色索引 ROM 和调色板 ROM。索引读占用原地址寄存器周期，调色板读占用原颜色寄存器周期。透明度通过非零索引提前判断，遮挡优先级不变。没有对 Logo 进行颜色量化。
- `hdmi_mixer_user.v`：匹配两个 ROM 的同步读，保持原输出数据、DE/HS/VS、读请求的周期对应关系。
- `ua_hand_profile.v`：列轮廓 `top_y` 改为预取同步 RAM；保留 `seen` 有效位，RAM 数据不作全阵列复位或清零。PROFILE/SHOULDER 状态预取下一列，进入状态前预取第 0 列；无效项不会参与判断。
- 三色形状判断经检查已有帧末共享分类器和每色共享面积乘法器，本轮没有再改其周期或阈值。直方图和其他阵列也未为了节省资源冒险改变读写行为。

## 基线

v17 Routed：Slice 20268/21216；LUT6 19805；REG 18028；ERAM 74；DSP 15；SWNS +0.115 ns；HWNS +0.020 ns；STA coverage 94.36%。

原始源文件和报告另存于 `tmp/resource_a_v18_baseline/`，逐周期对照模块位于 `host/tests/fixtures/*v17_reference.v`。

## 验证与构建

```powershell
pwsh -NoProfile -File tools/test_resource_v18.ps1
pwsh -NoProfile -File tools/build_hdmi_v18.ps1
pwsh -NoProfile -File tools/build_hdmi_v18.ps1 -VerifyOnly
```

回归包含 4096 个字形行、32768 个 Logo 地址穷举；完整 HDMI 画面的新旧逐周期比较；亮/暗场和不同采样步长下手势结果/框坐标逐周期比较；原有手势防误检测试；AE、AWB、数码管、帧缓存和图像处理回归。测试标记代表对应仿真范围通过，不代表实物摄像头识别准确率提升。

本轮第一次候选只将 Logo 索引表 RAM 化，调色板仍用组合逻辑；随后改为同步调色板，并补充项目已有的安路 bram 存储属性，重新完整综合。探索候选的自有实现任务已经停止，不是交付版；最终物理分配以映射/布局报告为准，不能凭 RTL 数组尺寸声称使用了多少 ERAM。

## 最终交付结果

2026-10-13 完成完整 TD 6.2.168116 综合、布局布线及 bit 生成，源文件 224 项哈希与构建快照一致。最终 Routed 结果：

| 资源 | v17 | v18 | 变化 |
|---|---:|---:|---:|
| Slice | 20268 (95.53%) | 19096 (90.01%) | -1172 |
| LUT6 | 19805 | 18551 | -1254 |
| REG | 18028 | 16815 | -1213 |
| ERAM | 74 | 79 | +5 |
| DSP | 15 | 15 | 0 |

剩余 Slice 从 948 增到 2120。最终 SWNS +0.103 ns、HWNS +0.020 ns；STNS/HTNS 均为 0，STA coverage 94.48%。相对 v17，建立余量略减，因此不能声称时序改善；本轮目标是保持通过并降低资源。

完整回归标记：`RESOURCE_V18_REGRESSION_PASS_NOT_HARDWARE_SIGNOFF`。额外带三色/手势框的 921600 像素逐周期显示对照也通过。原有摄像头识别效果和画质问题不会因等价的资源优化自动改善；本轮不宣称实物识别准确率提高。

交付：`deliverables/camera_hdmi_v18_resource_a_20261013.bit`，1789536 字节。

SHA256：`32BAF63EDED61F3065A0FEC69F5D0B91663B02A44F2E2FFE64E1BA5839EEB6CB`。

核验：`tmp/v18_delivery_audit.json`；资源明细：`tmp/v18_resource_comparison.json`；构建日志：`prj/td_project/td_20261013_143637.log`；最终时序：`prj/td_project/camera_to_dsi_display_hdmi_pr.timing`。

未自动烧录。板上仍为用户之前烧录的版本；新 bit 的实物效果、启动显示、ROM 初始化以及长期运行需要上板核验。v17 回退 bit 保留。
