# Sobel / 素描 / 浮雕左右边界修复（v35）

## 已确认的问题

旧 `ua_user_algo_96.v` 的行尾会清零窗口、mag、sobel_v 和 emboss_v，但与该行对应的源流还要经过固定 8 拍流水才能输出。提前清零会覆盖尚未输出的行尾结果。浮雕另有 `legacy_last_group_ok`，直接把最后 4 像素组强制填黑。

原行缓存使用 `line_mem[x_grp] <= {mid_v,smooth_gray}`，其中 mid_v 已来自前一拍、前一列的读数据，写地址却已推进到下一列；帧首读写也没有一致使用 SOF 对应的 0 地址。行首清零又会制造高反差假边。

旧右侧补丁只对最后 4 组重新做 Sobel，使用独立的最后 6 组缓存，和主支路的平滑及流水规则不一致；浮雕仍使用原来的被清零结果。只调整描边阈值或扩展该补丁不能修复这些对齐问题。

## 实现

- 使用一条统一的两行灰度缓存，320×16 bit，同一地址完成读取与下一拍写回。无新增整帧缓存。
- TD 使用无复位的寄存读地址模板，避免输出寄存器被吸收到有复位的窗口逻辑后退化为分布式 RAM。第一个候选的 DRAM 映射已停止并保留日志，不作为最终交付。
- 水平 `[1,2,1]/4` 平滑、因果 3×3 窗口都按有效样本推进；左侧和顶部缺失邻居使用边界复制。窗口只使用当前及过去的列/行，不需要丢弃右侧或底部有效像素。
- Sobel、二值、素描、浮雕、卡通描边结果与源 RGB、mode、valid/user/last 都固定延迟 8 个时钟。算术流水每拍推进，行缓存和邻域历史只在有效样本时推进。
- 删除提前行尾清零、末组强制填黑和独立右侧补丁；卡通描边连续性历史按输出有效拍和行坐标更新。
- 仍为每组 4 像素的灰度运算分辨率，卡通颜色映射表不变；本次不增加算法的空间采样分辨率。

## 验证方法

测试台 `host/tests/tb_algo_line_boundaries.sv` 使用独立整数参考核，逐组比较图像值和固定 8 拍边带，而非只检查最后有多少输出。

- 同一测试可复现旧版 2,118 组不匹配，包含左侧假边和右侧输出错误；旧版 fixture 仅供回归、不参与综合。
- 小尺寸覆盖宽度 8/12/32/80/1280、7 个模式、4 种图案，包括均匀灰、行列编码、右侧强边与左侧变化。
- 720p 覆盖模式 2–6、3 种图案，分别测试连续输入和 valid 气泡/变化行间空白，共 6,912,000 组（27,648,000 像素）。检查全行含首末组、首末行及行末冲出。
- 模式 2–5 比较精确灰度值，模式 6 比较黑色描边掩膜；未把未修改的颜色映射用另一个近似调色模型代替。
- 可复现命令：`./tools/test_algo_boundaries.ps1`；验证输入 SHA256 记录于 `tmp/v35_algorithm_verification.json`。

## 构建与部署

- TD 6.2.168116，顶层 `design_top_user`，器件 `PH1P35MDG324`。最终 Routed：SWNS `+0.112 ns`，HWNS `+0.020 ns`，STNS/HTNS `0`。
- 资源：Slice `19,969/21,216`（94.12%），比 v34 少 274；LUT6 `19,325`，REG `17,307`，ERAM `105/108`，DSP `19/40`。
- bit：`deliverables/camera_hdmi_v35_window_border_fix.bit`；SHA256 `D4FF2DB2F3C8BA69BE016D5645A81DDF3C5AAE3185BFD0B844BB37AAA1ACA2EA`。
- 原全流程已经完成布线、所有时序非负；其交付阶段的 `get_clocks` 数量检查未通过。最终通过重新导入同一个 routed DB、准确解析映射后同步器和实际 50MHz 时钟报告完成复核，生成 bit；没有更改 routed DB、RTL、引脚或时钟周期。记录在 `tmp/v35_finalize.log` 与 `tmp/v35_fpga_build_result.json`。
- 已于 2026-10-16 通过终端下载 FPGA SRAM，并恢复 MCU v34 到 TCM；没有写 Flash、没有开启舵机。BitWriter 最终状态检查复现旧的 `PRG-9507 line 29455519`，独立只读核验 ID `4808f0e7`、配置状态 `A9C0125D`（DONE=1），按这一证据确认下载，未伪记为原生最终检查通过。
- FPGA 凭据 `tmp/v35_fpga_sram_programmed.json`，MCU 凭据 `tmp/v35_mcu_native_deployment.json`。MCU ELF SHA256 `BF4D1310345E9967CAC37ED851A224046F86D4F0C09B0792552F40048C0ED6AD`，GDB 对下载段比对一致。
- 板上复查 `ARUCO frames=451 errors=0`、`TRACK armed=0 remaining=0 faults=0`，说明采集和 MCU 任务持续运行。当前无有效标记。记录 `tmp/v35_runtime_after.log`。
- 所有构建/MCU 输入哈希与下载文件最终复核一致。显示器实际左右边界的视觉改善仍需用户在模式 2/4/5/6 观察；本轮没有从 OBS 抓取下载后的画面，不能将仿真通过表述为实拍确认。
- 构建复现：运行 `tools/test_algo_boundaries.ps1`，再运行 `tools/build_hdmi_v35.ps1`；若仅在终端的时钟对象数量检查处停止，使用 `tools/complete_hdmi_v35.ps1` 对同一 routed DB 最终复核并生成 bit，不需重复 P&R。
