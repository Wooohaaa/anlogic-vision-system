# ArUco 透视描边与 MCU 取帧提速（v34 已部署）

## 本轮实现

- MCU 优先发布检测器亚像素细化后的四角；细化失败时回退到原始四角。
- 将四个角点和四条边的定点直线参数经 AHB 提交到 HDMI 域。像素混合器逐边绘制透视四边形，不再把标记压成水平/垂直外接框。直线使用 Q10 斜率、半像素截距和主轴标志；显示像素管线不执行除法。
- ArUco OSD 仍无新增帧缓存；ID 标签的位置继续按四角外接范围放置。
- MCU 对 160×90 灰度快照只做一次 FPGA AHB 读取，压成每像素 4-bit 的 7,200-byte TCM 缓存。Otsu 直方图使用 16 档；后续阈值扫描、候选解码和边缘细化均读本地缓存。
- 连通域阶段改为在一趟扫描中按阈值取像素并标记 visited，删除旧的完整二值图生成遍历。
- `ua_aruco_step` 预算从 16 提到 64 个像素/节点每次前台调用；每次检测仍保持原先约 100ms 的启动间隔。

## MCU 构建

`build_aruco.ps1 -Revision v34` 已完成交叉编译，结果为 `BUILD_VERIFIED_NOT_PROGRAMMED`：

- ELF：`deliverables/mcu_aruco_v34.elf`
- SHA256：`BF4D1310345E9967CAC37ED851A224046F86D4F0C09B0792552F40048C0ED6AD`
- `text+data+bss`：44,424 / 49,152 bytes（约 90.4%）；link map 中 stack 2,048 bytes、heap 1,024 bytes 已计入该总量，尚余约 4,728 bytes。
- 2026-10-16 已加载到 MCU TCM，GDB `compare-sections` 对 `.init/.config_settings/.text/.data` 全部回报 matched；运行确认 `armed=0 remaining=0 faults=0`、硬件 PWM 关闭。未写 Flash。

## FPGA 构建与部署

- 用户本轮授权助手完成综合与部署，TD 6.2.168116 全流程完成，顶层 `design_top_user`，器件 `PH1P35MDG324`。
- bit：`deliverables/camera_hdmi_v34_aruco_perspective.bit`。
- SHA256：`A82A0333B908D5EF0C45544CEFBDEC6A2AB7A7A539AF0E2875E0A28AAB09184F`。
- 最终 Routed：SWNS `+0.105 ns`，HWNS `+0.020 ns`，STNS/HTNS `0`。
- 初始综合阶段的 SW2 第一同步级约束因使用映射后的寄存器名而报空集合；对同一个 routed DB 重新读取约束后，确认只命中 `detect_sync_reg[0]_syn_2` 一格，独立最终时序审计通过，裕量仍为上述数值，DB 和 bit 均未改变。审计凭据 `tmp/v34_final_timing_audit.json`，日志 `tmp/v34_final_timing_audit.log`。
- 资源：Slice `20,243/21,216`（95.41%），LUT6 `19,516`，REG `17,492`，ERAM `105/108`，DSP `19/40`。
- 经官方 BitWriter CLI 下载 SRAM，最后状态检查复现已知 `PRG-9507 line 29455519`。独立 OpenOCD 只读检查器件 ID `4808f0e7`、配置状态 `A9C0125D`（DONE=1），按这一独立证据记录部署完成，未把原生最终检查伪写为通过。没有重复下载，也未写 Flash。
- 构建凭据 `tmp/v34_fpga_build_result.json`；FPGA 下载凭据 `tmp/v34_fpga_sram_programmed.json`；MCU 下载凭据 `tmp/v34_mcu_native_deployment.json`。

## 仿真与运行证据

- 修复旧测试台的矩形框接口，统一为 v34 四角和边线寄存器。
- `tools/test_aruco_extended.ps1` 通过：必测图像场景 60/60，18 帧 RTL 验证，捕获/冻结/释放、AHB 错误恢复、50/25MHz 总线压力、PWM 关闭及运行时回归均通过。日志 `tmp/v34_aruco_regression.log`。本轮采用 Icarus 和 host C，没有运行 ModelSim。
- `tb_aruco_hdmi_path` 通过实际 AHB 写入、异步显示域 CDC、720p 全帧像素生成，得到倾斜四边形青色边线 2604 像素、ID 黄色像素 780，并验证 invalid 提交后清除。日志 `tmp/v34_hdmi_path.log`。
- 板上串口复查：处理帧数 `441 -> 452`，20ms 定时器计数 `7793 -> 7973`，采集错误 `0`，`faults=0`，舵机关闭。当前场景处理吞吐约 `11/(180*0.02)=3.06` 次/秒；这是当前无标记场景的一段观测，不是保证帧率。尚不能声称已达到流畅的标记跟随刷新率。
- 当前 `valid=0 id=255`，表示没有有效标记；检测任务已运行。启动后第一次状态为 disabled，后续正常扫描，不能用启动消抖窗口的单次状态判断 SW2 关闭。
- 功能开关为 SW2；检测成功时 HDMI 应显示贴合四角的青色轮廓和黄色十进制 ID。真实画面效果仍待用户观察，未声称已拍摄验证。

## 后续边界

- 相机内参与 ArUco 实际边长仍缺失，因此当前不显示 3D XYZ 坐标轴。取得棋盘格标定图和标记实测尺寸后再接入轴投影。
- 降低 AHB 读取次数与提高处理预算已落实；实测吞吐仍约 3 次/秒，后续应基于实板分段计时继续提速，而不能把仿真视频播放 FPS 当作硬件检测 FPS。
- 当前为 SRAM FPGA 配置与 MCU TCM，断电后恢复原 Flash 内容。
