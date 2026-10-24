# v88 手势失效与暗处边缘检查

## 边界

保留 v87 的颜色配置、HDMI 首行灰色覆盖和卡通描边空间对齐；不改 AWB、曝光、DDR、时钟约束、MCU v83 或电机控制，不开启电机。保留全部功能，最终占用要求 Slice <=19518/21216、ERAM <=108、DSP <=40。

## 录像与已确认问题

输入 `C:/Users/Chieh yu/Videos/2026-10-23 16-21-57.mp4`，1280×720、60 fps，实际解码644帧。SHA256：`071da665053eb8bfbaf140cf5494fd20ec088aa2f35563d7ea875191530296bc`。

这是压缩后的 HDMI 录像，含 OSD，不是原始传感器/ISP 输入。选取5帧重复2次的实际 RGB 手势 RTL，与参考模型一致；motion 到手势的实际采样连接也能产生 OPEN。它们不等于全视频识别准确率，不证明板上正常。放宽黄色肤色范围的离线试验增加背景干扰，未采用。

新增独立反例：采集一对像素后丢失 EOF，不再输入数据。旧核心在 WAIT_FRAME 持有单缓存，但原 watchdog 不计这个阶段，仿真复现永久等待。新版本：

- watchdog 覆盖采集和形态学的缓存持有期，空闲期不计时；回收时清零。
- 新帧先于旧帧 EOF 到达时，明确拒绝并释放旧采集，不静默泄漏缓存。
- 错误通过现有 T 字段显示7（不是手指数），正常拳头/无候选为0，张掌分支支持为3；不增加跨时钟总线。

这修复了确定存在的卡死路径，但尚不能确认就是录像中板上失效的唯一原因。不能将模型一致性称为识别已全面解决。

## 暗处边缘

仅在分组灰度低于64 DN、原始缩放梯度至少4 DN时，把边缘幅度提升两倍并饱和到255。小梯度不增强，降低暗噪声被描成边缘的风险。只作用于 Sobel/素描/卡通轮廓，直通颜色、灰度、二值化、浮雕不变，仍固定8时钟流水，不增加行缓存或DSP。

参数 `DARK_EDGE_ENABLE` 默认0供历史回归；整机显式设1。独立测试根据未截断的梯度重新计算幅度，避免先截断再乘2造成1 DN参考误差；检查有效气泡、首尾列、亮暗阶跃及水平/垂直/斜线描边。

## 状态

`tmp/v88_regression/result.json`：13组独立流/描边/恢复仿真通过；另有坏帧恢复、5个录像选帧各重复2次、8帧连续 motion 接入回归通过。选帧模型含误分类，未将其标为真实分类准确率通过。

附加 A/B 测试 `host/tests/tb_dark_edge_effect_v88.sv`：低亮16→40 DN边缘，旧卡通轮廓0行、新版24行，位置不偏移；±1 DN暗部扰动、亮处轮廓、任意RGB直通/灰度/二值/浮雕与旧参数版相同，比较6720组输出。

## 最终构建与部署

- 最终 Routed：Slice 19397/21216（91.43%，比v87少109），ERAM 97/108，DSP 32/40。
- SWNS +0.111 ns，HWNS +0.020 ns，STNS/HTNS均0，未放宽SDC。STA coverage 95.35%，并非所有路径都有覆盖。
- FPGA：`deliverables/camera_hdmi_v88_hand_edges_fpga.bit`，SHA256 `547ca14c36f0153c10e5f9d4634e45fb40697eee2d51e050140ef682c3d91706`。
- 联合Flash：`deliverables/camera_hdmi_v88_fpga_mcu_flash.bit`，SHA256 `0337ecddad1c2cd0094a44bf86d1ecf3a6532124702512b428d51b90e2670eea`。
- MCU保持v83，ELF SHA256 `32cb03c1738a0ea1bbeed88f342f84f519221f5a93aa6f60bcf11afb5e565827`；默认电机关闭。
- 官方BitWriter终端单次 program_spi -v 成功：PH1P35MDG324 器件确认、Chip validation success、Page program and verify、V88_FLASH_PROGRAM_VERIFY_COMPLETE。耗时104.62秒，无USB错误，没有重复烧录或电机操作。
- `tmp/v88_pipeline_result.json` 最终 `FLASH_PROGRAMMED_VERIFY_PASS`，2026-10-23 18:33:26 +08:00。独立重新核对600项冻结输入及FPGA/联合镜像SHA256匹配。

Flash校验成功不等于冷启动和真实识别已验证；需用户重启后观察。手势仍有离线误分类/漏检，不能称全面解决。T:7可区分错误帧与正常无候选T:0，以便继续定位板上问题。
