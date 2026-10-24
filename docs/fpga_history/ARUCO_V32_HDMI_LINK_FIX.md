# v32 ArUco HDMI 连接修复（2026-10-16）

## 已定位的问题

MCU v33 在板上可持续识别 ID23（`valid=1, errors=0`），MMIO `0x80000110` 读回 `0x80000023`，四个矩形边界寄存器有正常像素坐标。但 HDMI 未出现框或 ID。

v31 的 TD 日志 `prj/td_project/td_20261016_154403.log` 明确报告：

- 顶层 HDMI 连接处 `S_aruco_display_*` 未声明，被假定为隐式 wire。
- ID 端口实际宽度 1、期望 12；坐标端口实际宽度 1、期望 11。

这些信号实际声明在 `gen_ae` generate 块内。MCU 结果寄存器与独立 OSD 模块各自通过测试，并不意味着顶层连线正确。旧测试缺少顶层连接检查。

## 修改范围

只将 `rtl/user/design_top_user.v` 中六个 HDMI ArUco 结果输入改为显式 `gen_ae.S_aruco_display_*` 层级连接；不改变相机、DDR、识别算法、曝光、白平衡或舵机逻辑。

新增验证：

- `host/tests/test_aruco_top_links.py`：校验实际顶层六根信号；负例证明能抓到 v31 的漏层级问题。
- `host/tests/tb_aruco_hdmi_path.sv`：通过实际 AHB 外设写入 ID23 / 框 (200,80)-(600,360)，经实际显示 CDC、实际 mixer 和字体 ROM，检查最终 HDMI 像素。Logo 使用现有仿真契约模型，不是加密厂商模型。
- 整帧仿真结果：`ARUCO_HDMI_PATH_PASS cyan=2640 yellow=780 commits=1`。
- v32 构建流程拒绝 ArUco 的未声明信号及端口位宽告警，另外要求 Routed 非负 SWNS/HWNS/STNS/HTNS 与输入 SHA256 一致。

## 构建与部署

构建：`tools/build_hdmi_v32.ps1`；原生 SRAM 部署：`tools/program_hdmi_v32_native.ps1`；随后用 `../mcu_tracking/load_aruco_v33_native.ps1 -FpgaRevision v32` 恢复 MCU TCM。全部不写 Flash，不启用舵机。

## 最终结果

- 显示链路整帧仿真、顶层连接正反例和已有扩展回归通过（61 个图像案例、18 个 RTL 帧）。
- 最终 Routed：SWNS +0.121 ns，HWNS +0.020 ns，STNS/HTNS 均为 0，STA 覆盖率 94.58%。Slice 19,569/21,216（92.24%），LUT6 18,976，REG 17,055，ERAM 105，DSP 15。
- 初次布局布线只有一条未通过的 SW2 控制跨域保持路径：100 MHz 开关输出到 `detect_sync[0]`。最终补充仅限来源 100 MHz 到接收第一级的 CDC 例外；第二级在 50 MHz 域，未放宽时钟或屏蔽整个时钟组。查询确认只命中一个第一级单元。物理路由数据库未变，SHA256 为 `79F19E51BC4ACE87658A8A38E38B925F7C0BAA201CA80CED87D105E2EAB7323B`。
- FPGA bit SHA256：`2E28CE077E55E9980EAC71033BDBD9472C4908BA3D655B473352BD48748155D1`。
- FPGA 已加载 SRAM。原生下载末尾仍出现已知状态检查错误，不能称原生检查通过；独立读回 PH1P35 配置 ID `4808f0e7`、状态 `A9C0125D`（DONE=1），记录于 `tmp/v32_fpga_sram_programmed.json`。
- MCU v33 已重新加载 TCM，四个程序段全部读回 matched；ELF SHA256 `E1A074F28747C10CB1C958050EB17F885FC8ABF91B2B473FFD315577B4371BF7`。第一次大包 RSP 校验通信失败已保留日志，改为 256 字节远程读写包后校验成功。
- 串口确认运行、图像处理帧计数前进、errors=0、faults=0、armed=0、remaining=0，未写 Flash，未启用舵机。

真实 HDMI 上的框和 ID 仍待用户目视确认；不以仿真像素或寄存器结果替代实际显示验证。尚未进行相机标定，因此不宣称位姿估计已在当前相机上验证。
