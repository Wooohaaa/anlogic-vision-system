# FPGA视频处理与视觉识别工程

工程基于PH1P35MDG324与MIPI摄像头，以四像素并行流水线处理1280×720视频，通过DDR缓存并输出HDMI。功能包括自动白平衡、曝光与亮度控制、降噪、七种图像模式、颜色形状、运动区域、张掌握拳和单张数字卡识别，以及板内MCU协作的ArUco显示与双步进云台跟踪。

rtl/user是维护RTL，rtl/official保存接口模块；prj包含TD工程及约束，host/tests包含测试台。tools/build.py同步维护源到工程生成目录。根目录tools/repository.py提供setup、verify、test、mcu、fpga、flash-image和program入口。

HDMI叠加Logo、模式、链路延迟、IN/OUT输入输出帧率及识别框。完整功能与操作参见仓库根目录README和docs中的技术文档。
