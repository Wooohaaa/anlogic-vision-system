# v92：运动网格、区域框与百分比

## 目标与边界

赛题二要求硬件运动检测并叠加运动区域提示或计数。v92在v91弱边缘版本基础上增加独立黄色运动框与MOV百分比，不是光流、不做目标身份识别。用户将本轮Slice上限改为20000；ERAM<=108、DSP<=40，原MCU v83不变，不启用电机。

## 实现

1. 复用原运动参考RAM，以四像素灰度组均值、每四行采样进行相邻帧差。生产实例关闭背景冻结；手势采样/帧结束和RGB路径保持原接口，手势分类仍不依赖运动命中。
2. 普通差分阈值24；当前与参考均低于96 DN时阈值16。初始化参考期间不产生有效运动命中；暗部增益档位变化请求重新建立完整参考帧。
3. 32×32像素网格，至少4个差分命中采样组才认可该格。每列只存一个饱和计数，不保存网格全帧，既有参考帧RAM之外不新增图像缓存。1280×720共有40×23=920格，底行网格只覆盖16像素高度。
4. 输出有效网格的联合外接框；多目标第一版可能合为一个框。网格边界粗定位，不承诺贴合物体或亚像素描边。
5. MOV=floor(100×有效网格数/920)，表示网格占比，不是像素占比、速度、置信度、物体数量。百分比用100次串行加法/比较完成，不推断通用除法器。运动消失后框保持两帧，MOV立即归零。
6. 监测真实步进输出边沿，两级同步到摄像头域。当前帧有脉冲或最近三帧有脉冲时，结果置CAM，运动框隐藏、百分比0；屏幕改为CAM:ON。只利用脉冲估计相机运动，不能检测手动搬动相机或机械余振；不是光流稳像。
7. 将相机运动标志、有效框、百分比和四角坐标打包为53位。握手邮箱保持源数据到确认，多位结果不逐位独立采样；忙时丢弃新提交而非撕裂旧包。HDMI只在帧首提交结果，颜色/形状、手势、ArUco及文字保留原优先级。
8. SW1仍同时控制颜色/形状与运动显示。黄色细框是运动区域，与红绿蓝颜色框不同。未新占用按键/拨码，不修改步进控制策略。
9. 修复8位初始化帧计数器持续加到255回绕的问题：现在达到2后饱和，只有明确背景重建才重新进入初始化阶段。
10. 原精简字库补回一个百分号，复用相同1024×16 ROM，不恢复其他汉字或增大ROM。

## 测试与构建入口

- `tools/test_motion_view_v92.py`：18组ModelSim自检，包含280帧连续/气泡输入、超过256帧计数、1280×720全尺寸场景、噪声过滤、停住/移除、全画面变化、CAM抑制、背景重建与缺失EOF后恢复、异步时钟邮箱、整帧HDMI坐标及帧内更新不撕裂、原黑边/颜色保护、v91边缘与手势错误帧恢复。最终以receipt为准，不把仅编译通过当测试通过。
- `tools/build.py setup --binary-hand`同步新增模块和字体；维护源新增ua_motion_grid.v，工程条目108个。
- `tools/deploy_motion_view_v92.py`：独立v92日志/产物，先回归再综合布局，检查20000 Slice上限，再布线和最终Routed时序，最后封装原MCU v83联合Flash，通过才使用官方命令行烧录一次。不得重复下载已有成功版本。
- 流水线状态：`tmp/v92_pipeline_result.json`；回归：`tmp/v92_regression/result.json`；最终构建：`tmp/v92_build_result.json`；Flash成功：`tmp/v92_flash_programmed.json`。
- 第一轮ModelSim在显示模块声明顺序处报错，Icarus允许的前向变量引用被ModelSim拒绝。已前移坐标声明，失败日志保留于`tmp/v92_regression_first_compile_failure`；后续完整重跑，未因失败绕过检查或烧录。

## 待实机验收

- 固定摄像头：空桌静止接近0；物体移动出现黄色网格外接框；停住后MOV回0，框两帧后消失；撤走时再次出现变化框。
- 暗场和噪声：检查零散闪点是否被过滤；小于32像素/对比度低的目标可能漏检，必要时再调MIN_HITS，不能无条件放宽。
- 灯光突变：可能整屏运动，当前未做全局亮度补偿；MOV100%不是检测到一个巨大物体。光照下的稳定性需实拍，不能称完全抑制AE/AWB变化误报。
- 云台：有实际步进脉冲时显示CAM:ON，停止后三个安静帧后恢复。此状态是脉冲提示，非相机惯性测量。
- 比较高速往返时的框延迟：网格结果来自上一帧，此外还有显示缓存和帧首提交延迟，未做预测补偿，不承诺零延迟。
- 对比v91颜色、描边、AE/AWB、数字、手势和ArUco是否保持；真实板上准确率仍需用户确认。

## v92撤回与v92r1

v92模块级18组回归通过，但只读布局网表核验发现u_grid、u_motion_mailbox、u_compact_ref均为0，ERAM意外减少27块。原因是顶层新信号位于gen_ae作用域，外部HDMI实例却使用未加前缀的名字，TD按1位隐式线处理，裁掉了无人消费的运动链。该版19193 Slice/70 ERAM不是有效功能实现，不能宣传为资源优化。

在自动烧录之前已停止Python部署编排器，保留正在有进展的TD布线运行直到结束；未访问JTAG或生成联合镜像、没有Flash烧录尝试。即使撤回版生成了单独bit，也严禁烧录。记录为`tmp/v92_pipeline_result.json` WITHDRAWN_TOP_SCOPE_DISCONNECTED_NOT_PROGRAMMED。

v92r1将HDMI连接改为`gen_ae.S_motion_view_hdmi`及对应valid，新增顶层连接静态断言。布局后在布线脚本入口强制检查参考RAM、网格、邮箱及显示帧寄存器的网表单元数，不为0才继续；不是仅凭模块被elaborate就判断功能存在。

当前维护入口改为`tools/deploy_motion_view_v92r1.py`、`tools/test_motion_view_v92r1.py`，状态/回执/固件全部使用v92r1命名，保留旧失败历史。完整回归重跑，待最终资源/时序与烧录回执，不引用撤回版数据。

MOV不足1%时整数显示000%，运动框仍可能存在；这是整数显示精度，不是漏掉该网格。不能把MOV000%当作严格无运动判据。

## 最终v92r1结果（2026-10-24）

- 18组ModelSim回归全部通过，最终receipt `tmp/v92r1_regression/result.json`：V92R1_MOTION_VIEW_RTL_PASS_NOT_BOARD；含顶层作用域静态断言。回归与构建冻结输入哈希在烧录前独立核对一致。
- 布局/最终Routed资源：Slice19605/21216（92.41%，较v91增加196，距20000上限余395）；ERAM97/108、DSP32/40，均不增加。
- 布线入口强制确认：参考缓存27个单元、网格231、邮箱42、显示帧寄存器18，完整功能未被裁掉。
- 最终Confidence Routed，SWNS +0.140ns，HWNS +0.020ns，STNS/HTNS均0；STA coverage95.33%。SDC未变，既有厂商IP/前期约束告警仍按整体审计说明保留，不称完整CDC/I/O形式签核。
- FPGA bit：`deliverables/camera_hdmi_v92r1_motion_view_fpga.bit`，SHA256 `346b69e229d719f22853e89a49f66e1253ccbde0abf86066b0675a880d271cd5`。
- 联合Flash：`deliverables/camera_hdmi_v92r1_fpga_mcu_flash.bit`，SHA256 `47bc10b10db5e9b13dbf6dd976469e475ce63db0362bb2418401e86b16ce1ed2`，包含未修改的MCU v83。
- 北京时间14:07，官方BitWriter原生命令行一次SPI Flash写入及校验成功，目标PH1P35MDG324。`tmp/v92r1_pipeline_result.json`为FLASH_PROGRAMMED_VERIFY_PASS，烧录receipt为FLASH_PROGRAMMED_NATIVE_VERIFY_PASS_COLD_BOOT_PENDING。
- 烧录后镜像SHA与成功receipt再次独立匹配，没有重复下载或发送电机开启命令。尚未独立确认冷启动、板上画面及真实误报率，需用户重启后按上述场景验收。
- 撤回的v92单独bit移出交付目录，保留于`tmp/v92_withdrawn_not_for_programming/camera_hdmi_v92_WITHDRAWN_DO_NOT_PROGRAM.bit`，不可烧录；未删除其失败历史。
