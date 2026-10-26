# 自主架构 HDMI 媒体播放器

**接续入口：[HANDOFF.md](HANDOFF.md)** · [剩余任务](NEXT_TASKS.md) · [给DeepSeek harness的提示词](DEEPSEEK_PROMPT.md) · [当前进度45/100](PROGRESS.md)

## 最终验收目标

在 HX4S20C / EG4S20BG256 上实现与参考例程有实质区别的资源管理、图片处理、播放控制及音频处理，满足至少四张 640×480、24 位图片、手动切图、可配置自动轮播、稳定 HDMI 图像和音频输出。

正式路线：FAT32 目录与簇链读取 → 自主 BMP 解码 → 四图驻留 SDRAM → 帧边界选择 → 自主像素处理 → HDMI。后续音频另行实现文件型 PCM 读取、缓冲和图音关联；本轮暂缓音频。

本目录是新建正式源码目录。已有 ex4、ex5、三人共享区及队友文件均未被覆盖。原 ex4 仍是已通过部分板上测试的对照工程，不计作新架构的完成结果。

## 当前实现

- `rtl/storage/team_sector_guard.v`：512字节事务、超时和取消。
- `rtl/storage/team_fat32_mount.v`：MBR/卷参数解析与几何验证。
- `rtl/storage/team_fat32_catalog.v`：根目录簇链和BMP文件候选枚举。
- `rtl/storage/team_fat32_file_reader.v`：分散簇链文件读取、EOF和提前关闭。
- `rtl/image/team_bmp_parser.v`：自主文件字节流到 RGB888 像素流的解析器。
- `rtl/storage/team_frame_store_writer.v`：坐标到四帧字地址、写回应排空及帧有效性管理。
- `rtl/storage/team_image_loader.v`：FAT32文件读取、BMP解析、帧写入的生产连接模块。
- `rtl/video/team_frame_commit_bridge.v`：选择请求跨时钟传递及帧边界采纳回应。
- `docs/BMP接口.md`：接口、时序、错误状态和后级接入约定。
- `docs/FAT32接口.md`：只读子集、扇区接口与真实SPI适配要求。
- `docs/帧区与显示提交接口.md`：驻留策略、存储格式、接口及共同复位要求。
- `sim/bmp/tb_team_bmp_parser.sv`：独立验证的测试平台。
- `sim/bmp/fixtures/team_03.bmp`：团队已有的真实编号图副本，原素材未改。
- `tools/run_bmp_regression.py`：生成受控样本、调用仿真器、核对像素并保存新日志。
- `tools/run_fat32_regression.py`：卡镜像模型到文件字节/BMP像素的RTL联测。
- `tools/run_frame_regression.py`：帧区写入、文件加载器和跨域提交的25项联测。
- `PROGRESS.md`：以完整板上工程为分母的固定里程碑进度。
- `records/`：包含通过与失败的真实运行证据。

当前尚无新的整机 TD 工程或可下载配置，不能把解析模块的仿真成功当作新架构上板成功。

## 重复运行

需要Python 3.10+、`requirements-sim.txt`中的Pillow，以及已有Icarus安装。首次接手先运行`python tools/verify_handoff.py`核对冻结包；接续修改后旧manifest会报告正常的源码变化。

```powershell
python tools/run_bmp_regression.py
```

先将当前目录切到本README所在目录。三个脚本均支持`--iverilog-bin`或`IVERILOG_BIN`指定已有工具目录，也可发现本地私有运行时或PATH中的工具。Git交接包不含`.tools`，不依赖Codex私有Python路径。原环境Icarus13.0；Windows遇中文工具路径时复制已有运行时至ASCII临时目录。不修改系统PATH、注册表、TD或ModelSim配置，也不访问TF卡。Linux查找支持已实现但未实机复测。

每次运行均创建新的 `records/bmp_时间戳/`，通过标记为 `ALL_PASS cases=22`。已有日志不覆盖。对照像素由 Pillow 解码与独立样本生成器得到，不依赖待测 RTL 的计算结果。

FAT32联测（相同Python环境）：

```powershell
python tools/run_fat32_regression.py
```

该命令只使用新生成的卡镜像模型，不访问物理TF卡。当前29项案例包含MBR/无分区卷、活动FAT、簇大小、目录过滤、循环链、错误退出、提前关闭，以及四张完整分辨率图像的文件读取与解析。目录只发布候选，BMP解析成功才算合格图片。

四帧加载及帧边界提交联测：

```powershell
python tools/run_frame_regression.py
```

当前25项，包括两条各四张640×480图的完整案例、写入/文件收尾失败后的无效帧重试、帧区保护、背压，以及三种时钟比下的帧边界提交。RAM回应模型不是真实SDRAM控制器；提交桥不含显示读取和HDMI。日志每次新建，不覆盖旧证据。

也可使用现有 ModelSim：

```text
python tools/run_bmp_regression.py --engine modelsim --modelsim-bin D:\modeltech64_10.4\win64
```

本次命令行 ModelSim 编译成功但仿真启动报授权环境错误，因此实际回归使用 Icarus。该结果不推断用户 GUI 的授权状态。私有工具来自 MSYS2 官方 HTTPS 仓库；版本、URL 和 SHA-256 见 `records/toolchain_sources.json`，`.tools` 不应作为项目源码提交。

## 当前能力范围

- 默认接收宽 640、高正/负 480 的 24 位 BI_RGB BMP，支持 Windows DIB 头长度至少 40 字节。
- 从文件头读取像素偏移，支持扩展头、行补齐和正/负高度。
- 接收暂停、输出背压、传输中止和提前 EOF 都有明确定义。
- 每个像素带从左上角开始的 x/y 坐标；像素输出的先后顺序仍沿文件行顺序。底部向上存放的 BMP 不会被假装重排为顶部向下的字节流，后级必须使用输出坐标写帧存储。
- 已在卡镜像/RAM回应模型中串联FAT文件读取、BMP解析和四帧加载。成功帧保持只读；真实SD扇区适配、SDRAM调度、整机启动控制与HDMI尚未接入，没有新整机的TD综合、时序或板上证据。

## 复用边界

`team_bmp_parser.v` 是本轮独立实现的应用逻辑，未导入参考 `bmp_read.v`。板卡引脚、厂商原语、HDMI IP 和底层存储驱动的最终复用边界仍需向赛方确认。源码来源和工程差异说明不能替代赛方的最终认定。

