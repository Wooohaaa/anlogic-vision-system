# v84：卡通描边空间对齐与顶部异常颜色行

> **2026-10-22 实板回归后撤回 v84r1。不要再次部署该镜像。已恢复 v83 Flash，等待用户重启确认。**

## 实板失败与根因复现（优先于下文的历史构建结果）

用户视频 2026-10-22 20-21-19.mp4 显示图像/OSD仍更新，但延迟为 `---`、手势无结果，并报告颜色形状和 ArUco 均失效。

新增 host/tests/tb_v84r1_awb_regression.sv，连接真实生产 ua_awb_frame、signal_delay 和延时 RAM，而非理想流接口：输入 1280×8、两帧、每行有 100 拍空白。原路径输出 5120 组、16 个正确行尾；v84r1 路径仅输出 4482 组、12 个行尾，2 行宽度错误，成功复现 V84R1_AWB_LINE_CONTRACT_REGRESSION_REPRODUCED。

根因是行缓存尾部两行连续刷新。AWB 的延时读控制依赖固定行节拍，O_tlast 用 valid 下降沿重建，不传递 I_tlast。独立 row-cache 的显式 EOL 正确，并不保证真实 AWB 后级仍得到正确帧宽/帧高；此前组件回归漏掉了此接口契约。多个检测器拒绝坏帧与用户现象一致；不能把原组件通过和最终时序通过等同于整机功能通过。

处理：v84r1 撤回；生产 isp_top_user.v 已取消首行缓存接入，build.py 取消实验模块的部署清单，恢复原公共 demosaic→AWB 接口。实验模块及全部失败/通过记录保留，用于根因回归，不再以现有脚本部署。卡通空间修正代码保留为待重新集成验证的维护源；本次实际回退的 FPGA/MCU 镜像都是 v83，不包含此修正。

回退首次读 ID 遇 USB transfer failed，未写入；用户重新插拔并明确回复“好了”后，一次重试官方 SPI Flash program and verify 成功（约 102.5 秒），标记 RESTORE_V83_FLASH_VERIFY_COMPLETE。成功记录 tmp/rollback_v83_after_v84r1_result.json，联合 SHA 为 `0fa1c4174ec4e5a9675b574ba0acb5b4e351db28742067cb2cec7ccce72cef60`。未发运动命令，保留 KEY2；需用户断电重启并确认各功能恢复。

## 诊断与改动

原卡通底色是当前输入组，但边缘来自水平方向 `[1,2,1]/4` 的因果平滑，再加后向 3×3 Sobel。其窗口中心相对底色滞后约两组（8 像素）和一行。统一 8 拍时钟延迟只解决流水对齐，不能解决这个空间错位。独立阶跃测试中旧参考 RTL 确实失败。

新卡通描边使用当前组与左邻组、同列上一行的差分，绝对值和除以 2，并保留现有强/弱边缘门限和弱边缘连续性条件。复用原有绝对值、求和与输出流水，不另造第二套运算器。灰度历史高字节增加当前组均值；卡通底色函数不改，模式 0～5 的原计算不改。组域描边仍为 4 像素宽的粒度，不声称亚像素或完整每像素 Sobel。

活动路径是恢复后的官方 legacy demosaic，而不是 ua_demosaic_border 实验路径。legacy 在首行把同一 Bayer 行当作上下行，并用错误 CFA 行颜色。已有独立插值器测试复现红通道 100，而真实均匀场应为 40；这能解释顶部细颜色行，但仍需实板验证它是否解释了用户照片的全部现象。

新增 ua_top_row_repair_96，插在 demosaic 后、AWB 前。只用下一条已解码行替代错误的首行，不黑屏裁切、不换 Bayer 模式；后续各行逐像素保留，尾部从缓存刷新出来，帧尺寸不变。首版为一行前视，但布局 Slice 19688（92.80%），被占用门限拦截，未布线和烧录。

v84r1 改为三行循环缓存、两行前视：当前输入行写入一 bank，输出从其他 bank 读取，避免同址读写；首两条输出行都读取已解码的 row1，后续行按原顺序输出。删除 96 位旁路选择及两套像素寄存器，以 RAM 换取 Slice。代价是约两行时间延迟、三行 RGB RAM，以及首行真实独立纹理的牺牲。坏行不再进入 AWB 和检测统计，而不是仅在 HDMI 上遮挡。需要帧间空白至少 2*WIDTH/4+2 时钟完成尾部两行刷新；当前 720p 相机有垂直消隐，尚待上板核验。现有 isp_top_user 接入注释沿用首版 One-row 字样，精确实现及延迟以模块头和本记录为准。

KEY2 开关、MCU v83、所有检测、曝光及色调参数保持不变；上电默认电机 OFF，不发送运动命令。

## 验证与构建

针对性回归覆盖恒定场、水平/垂直/斜阶跃、最右侧边缘，连续流与 valid 气泡，填满 RAM 后复位、短首行后新 SOF、多帧及 EOF 刷新。至少包括 1280×720 完整帧。非卡通模式由原独立边界模型对照。

构建工具 tools/deploy_alignment_v84.py 先回归、再综合布局，Slice 必须 ≤19518（92%），最终 Routed 时序通过才生成并烧录联合 Flash；MCU 使用已校验 v83 ELF。构建期间不修改冻结源，不重复启动或重复写入。

v84r1 首行循环缓存重新完成全部六组测试，包括 1280×720 的连续流/气泡和复位、多帧/短首行恢复。卡通与模式 0～5 重用 v84 回归，逐一核对全部未改测试及源码 SHA，不把改动过的行缓存回归当作可复用证据。

## 最终资源、时序和部署

v84r1 最终 Routed：Slice 19476/21216（91.80%），ERAM 102/108，DSP 32/40。比 v83 增加 12 Slice 和 5 ERAM。SWNS +0.108ns，HWNS +0.020ns，STNS/HTNS 均为 0。输入哈希在完成构建及烧录后独立复核通过。

- FPGA bit SHA256：`53bd55c451150253bd8ccb9eb1aa0ce8169461dfb3960bd93723ab9180a9c1b6`。
- 联合 Flash：`deliverables/camera_hdmi_v84r1_fpga_mcu_flash.bit`，SHA256 `d56f64ebff1315c9e83d0f2428147361acbebb12eaf3c626babbeae3870f0577`。
- MCU 仍为 v83 原 ELF，未重新编译、未改变 KEY2 或速度参数。Flash payload 的 version 字段仍为 83。
- 官方命令行识别 PH1P35MDG324 成功，执行一次 SPI Flash Page program and verify，约 105.7 秒，完成标记 V84R1_FLASH_PROGRAM_VERIFY_COMPLETE。未发生重试、未发送串口运动命令。
- 最终 receipt：tmp/v84r1_flash_programmed.json，状态 FLASH_PROGRAMMED_NATIVE_VERIFY_PASS_COLD_BOOT_PENDING；流水线 tmp/v84r1_pipeline_result.json 为 FLASH_PROGRAMMED_VERIFY_PASS。

已写入持久 Flash，需用户断电重启后观察直通顶部红线与卡通描边。冷启动、真实画质、相机实际消隐是否充分及机械 KEY2 效果尚未实板确认；不能把仿真和烧录成功称为最终画质保证。
