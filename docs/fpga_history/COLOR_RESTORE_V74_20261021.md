# v74：打印色卡画面发灰的第一轮色调修正

## 证据与边界

用户提供 `2026-10-21 16-52-55.mp4`（1280×720，实际解码37帧，约0.62秒）与打印色卡及OBS截图。录像是最终HDMI图像，不是线性RAW。`tools/analyze_chart_v74.py` 对12个固定内部小窗口测量；并未对每帧进行整张色卡的几何标定。

录像浅绿块中位RGB约(140,172,125)，黄色约(197,199,156)，色差显著偏小；但纸张、墨水、光源均影响实物色卡，不能把纸上标注的RGB当作实测反射率，不能据此宣称标定出准确CCM或DeltaE。已向用户请求同光照下实际打印色卡的手机照片。

当前9-bit公共ISP的独立通道编码、暗部提升和高光肩部会缩小一部分颜色的通道差。v74先做低风险、可回退的显示色调修正，不盲目加入固定红/绿通道增益，也不声称已定位全部物理偏色原因。

## 实现与契约

- `ua_photo_finish_96.v`增加默认关闭的`COLOR_RESTORE`，产品`isp_top_user.v`显式启用。仅9-bit生产路径应用，历史8-bit调用与默认关闭路径保持原行为。
- 在既有ROM初始化时，折叠公共RGB分段曲线：输入/输出锚点为(0,0)、(16,10)、(32,22)、(64,48)、(96,80)、(128,116)、(160,155)、(192,196)、(224,232)、(240,246)、(255,255)。温和降低灰雾、中间层拉开色差，高光保留肩部。它不是相机色度矩阵，也不能修复已经截断的高光。
- 原始黑位、AWB、曝光统计/反馈、5×5有限窗降噪、饱和度保护、全部检测/显示、MCU及电机控制不改。公共图像变化仍可能影响检测输入，真实检测效果需板上核验。
- 常数插值只在ROM初始化求值；不在像素路径新增乘法/除法、RAM bank或处理拍数。保留原4像素/拍、有效数据及SOF/EOL时序。是否仍在92%以内，以最终TD面积为准，不把结构预期当作综合结果。

## 验证与部署

- `tools/test_color_v74.py`独立Python模型对照RTL，覆盖2048项ROM、各强度曲线单调性、灰阶不染色、黑位零点、高光不额外提亮、帧内强度锁定、复位脏历史、气泡、行首行尾和完整720p帧。结果在`tmp/v74_color/result.json`，通过后才进入构建。
- v73旧源码快照保存为`host/tests/reference/ua_photo_finish_v73_reference.v`，SHA与v73冻结输入一致。旧版bit与所有成功下载记录保留。
- `tools/deploy_v74.py`先核对相对v73仅两处维护RTL改变；复用源码未变且哈希一致的组件仿真，重跑曝光回归，冻结新输入后综合/布局。Slice上限19518、ERAM108、DSP40；不满足则停止，不进入长布线/下载。
- Routed所有SWNS/HWNS非负、STNS/HTNS为零，验证bit、联合Flash载荷CRC及输入hash后，通过官方BitWriter终端仅烧录一次联合Flash。MCU保持步进＋ArUco v69；电机默认OFF，不进行串口运动或自动扫描。

当前验证：五组尺寸/位宽/气泡用例全部通过，其中连续1280×16和带气泡1280×720各三帧；完整720p对照2,764,800有效像素。独立`tools/test_color_exhaustive_v74.py`核对六个ROM的全部12,288字节，结果`tmp/v74_exhaustive/result.json`通过。曝光/统计/I2C八组回归也通过。合成颜色在强度2时，红样本通道跨度由93增至113，绿由83增至103，蓝由130增至154；这只是指定线性合成输入的模型结果，不是用户打印色卡的实测改善。

## 最终构建与下载记录

- 最终Routed：19490/21216 Slice（91.86%）、97/108 ERAM、32/40 DSP，与v73资源一致。Confidence=Routed，Slow/Fast两角；SWNS=+0.048ns、HWNS=+0.020ns，STNS=HTNS=0。STA coverage=95.31%，不代表所有外部异步接口均全面计时。
- FPGA镜像：`deliverables/camera_hdmi_v74_color_fpga.bit`，SHA256 `1169127453482E15FF8C3E8370549C9FFD22DCDAD4D69F9D79F374CE2322EBBE`。
- 联合Flash镜像：`deliverables/camera_hdmi_v74_fpga_mcu_flash.bit`，SHA256 `B4FC937FC53D84A132A618818782649BFA1454D870662F4FEC009C2E2B296C7A`。包含原步进＋ArUco MCU v69，没有增加MCU工作。
- 初次下载在读取ID时发生`PRG-8000 transfer failed`，尚未调用download，保留`tmp/v74_flash_program.log`。用户要求继续后，`tools/program_v74_ready.py`先确认前次未写Flash、无成功记录，核验冻结输入/仿真/bit/timing，再恢复已知官方服务并进行一次新尝试；未重新构建或改驱动。
- 2026-10-21 18:26（Asia/Shanghai）官方BitWriter `program_spi -v`完成写入与校验，目标PH1P35MDG324；原生下载102.010368秒。证据为`tmp/v74_flash_program_resume1.log`与`tmp/v74_flash_programmed.json`，状态`FLASH_PROGRAMMED_NATIVE_VERIFY_PASS_COLD_BOOT_PENDING`。
- 电机保持默认OFF，没有串口运动/扫描、没有单独下载MCU SRAM。FPGA＋MCU非易失镜像已写入，但冷启动、真实色卡和检测效果仍待用户重新上电观察。不能把模型或合成色块效果称为真实摄像头已校准。
