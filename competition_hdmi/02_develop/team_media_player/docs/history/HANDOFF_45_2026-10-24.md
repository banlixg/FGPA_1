# 给接续队友与DeepSeek harness的交接

交接日期：2026-10-24。研发进度：**45 / 100**。原ex4有用户报告的板上显示/切图成功；新自主架构目前只有RTL编译和仿真证据，**没有新的TD整机工程、.bit或板上成功证据**。

仓库：`https://github.com/banlixg/FGPA_1`。本工程在仓库内的路径：`competition_hdmi/02_develop/team_media_player`。以下路径除另注明外都相对本工程根目录，各电脑不要求使用原作者盘符。

## 1. 先读哪些文件

1. 本文件与`PROGRESS.md`：当前完成状态和100%分母。
2. `docs/BMP接口.md`、`docs/FAT32接口.md`、`docs/帧区与显示提交接口.md`：生产接口及限制。
3. `NEXT_TASKS.md`：剩余任务的推荐次序与验收条件。
4. `docs/ARCHITECTURE_PROPOSAL_2026-10-24.md`：设计出发点，**是提案快照，不是完工证明**。其中建议模块名与现有代码不完全一致，以`rtl/`实际文件和接口为准。
5. `records/`的摘要、日志和验收记录：实际执行结果。旧失败日志保留，不能仅凭脚本末尾字符串认定成功。

给harness的自包含起始提示词在`DEEPSEEK_PROMPT.md`。普通Python脚本即可复测，不需要接入Codex服务或原作者账户。

## 2. 项目目的与规则边界

HX4S20C / EG4S20BG256板，实现至少4张640×480、24位BMP的自动发现与加载、稳定HDMI图片、手动下一张、启动/停止自动轮播且周期可配置，最终还要有稳定可识别的HDMI音频。

用户提供的赛题条款要求整体架构、音频和图片处理方法不能与参考例程相同。当前路线为：真正FAT32目录/簇链读取、自主BMP解析、启动时四图驻留、按显示帧边界提交、自主像素处理，后续文件型PCM音频。改名、换图、改参数或仅加字幕不构成架构差异。

厂商HDMI IP、PLL、FIFO、底层SD/SDRAM驱动到底允许复用到什么程度，**尚未获得赛方确认**。保留来源及差异说明，最终认定不能由本交接替代。不要恢复参考`sd_card_bmp`/`bmp_read`/双缓冲切图链路后声称已完成自主路线。

## 3. 实际已有代码

| 文件 | 已有能力 | 尚未覆盖 |
|---|---|---|
| rtl/storage/team_sector_guard.v | 512字节事务、长度/错误/超时、取消 | 真实SPI缓存适配 |
| rtl/storage/team_fat32_mount.v | MBR或无分区卷、FAT32几何检查、活动FAT | GPT、扩展分区、exFAT/FAT16 |
| rtl/storage/team_fat32_catalog.v | 根目录簇链、短文件名BMP候选、错误链检测 | 递归目录、长文件名展示；候选不是合格图片 |
| rtl/storage/team_fat32_file_reader.v | 分散簇链、文件字节流、结束/关闭/扇区排空 | 真实SD介质时序 |
| rtl/image/team_bmp_parser.v | RGB888、头校验、行填充、正负高度、坐标、背压 | 压缩BMP、32位或其他尺寸默认不接受 |
| rtl/storage/team_frame_store_writer.v | 四槽坐标写入、内存回应、完整性发布、失败重试、禁止覆盖有效槽 | 真SDRAM读写调度 |
| rtl/storage/team_image_loader.v | 文件读取→BMP→帧写入的真实生产连接，失败收尾后才能重开 | 挂载/枚举/找满四张的启动调度器 |
| rtl/video/team_frame_commit_bridge.v | 选择跨域、帧边界采纳、回应 | 按键、轮播、显示读取、像素处理、HDMI接入 |

默认四槽起始**字地址**：0、307200、614400、921600。每像素32位`{RGB888,8'h00}`；四槽合计4,915,200字节。21位地址按字解释。实际SDRAM容量/地址映射和保留区仍需硬件核实。

槽有效必须同时等待：BMP成功、文件干净收尾、全部内存写入实际成功。不能把写FIFO接受当成SDRAM落地。有效槽复位前不可重写。切图桥要求两个域共同复位；它没有自动清理旧读FIFO，也不证明新图首像素已显示。

## 4. 已有验证与进度含义

最初三轮分别完成22项BMP、29项FAT32、25项帧区/加载器/提交桥测试，共76项；生产RTL还通过ModelSim 10.4编译0错误0警告。ModelSim命令行仿真曾遇授权环境错误，因此实际仿真使用项目私有Icarus13.0。不要将编译、模型仿真、TD时序和真实上板混称通过。

本次GitHub交接为解决跨电脑工具路径而更新了仿真脚本，并已在无`.tools`的上传副本中复跑上述三套测试，22/29/25项全部通过。新的复测目录和结果在`records/交接复测_2026-10-24.md`，此前的历史日志保持原样。旧摘要中的本机绝对路径是历史记录，不能当成队友必须具备的目录。

进度固定权重：架构5/5，BMP10/10，FAT32文件20/20，四帧与存储10/20，显示交互0/15，音频0/15，整机/时序/板上/复现0/15，总45/100。交接、上传及修改测试脚本**不增加工程完工百分比**。

## 5. 队友如何复测

需要Python 3.10+、`requirements-sim.txt`中的Pillow，以及现有Icarus的`iverilog`和`vvp`。原环境使用Icarus13.0、Pillow12.3.0；其他Icarus版本尚未逐一验证。依赖安装由接手者选择自己的环境和目录，这些脚本不会自动安装软件。

在本工程目录运行：

```text
python tools/verify_handoff.py
python tools/run_bmp_regression.py
python tools/run_fat32_regression.py
python tools/run_frame_regression.py
```

工具查找支持`--iverilog-bin`明确指定目录、`IVERILOG_BIN`环境变量、本地`.tools/iverilog/mingw64/bin`或PATH。三个回归脚本均支持显式参数，例如：

```text
python tools/run_frame_regression.py --iverilog-bin D:/tools/iverilog/bin
```

FAT32和frame脚本支持`--case 案例名`选择性复跑。完整通过标记分别为`ALL_PASS cases=22`、`ALL_PASS cases=29`、`ALL_PASS cases=25`。脚本生成临时卡模型及RAM模型，不访问物理TF卡。新日志另建日期目录。

私有`.tools`运行时和系统许可证不入库；安装来源/包摘要在`records/toolchain_sources.json`。Windows脚本遇中文工具路径会把已有运行时复制到临时ASCII目录。已支持PATH/native工具名；Linux环境尚未实机复跑。ModelSim可用BMP脚本的`--engine modelsim --modelsim-bin ...`，勿修改或绕过许可证。

`verify_handoff.py`核对冻结交接包的SHA-256。后续合法修改自然会让旧基线校验报告CHANGED，不代表新工作无效；保留旧manifest作为接手时的基线，不用重算manifest掩盖改动。

## 6. 现有板卡对照工程在哪里

仓库根目录已有`B work/day5-6/lab_ex4_tf`，它是原图像例程对照。TD入口是`src/td_project/lab_ex5_i2s_v1.0.al`，名称虽然含ex5，实际是ex4纯图片工程。另一个`competition_hdmi/01_baseline`也有参考资料；不要混用同名不同版源码。

`docs/board_reference_manifest.json`登记本机已跑通对照版本的60份工程源文件、仓库内路径、SHA-256。与仓库`d399d175f5fdc73c04258b98e2fd4a0e6b8e16c1`核对，16份字节完全一致、44份仅换行不同，无内容缺失/差异。因此无需再拷贝一套厂商源码到新工程。

该对照工程的参考底层包括`SD/sd_card_top.v`、`SD/sd_card_sec_read_write.v`、`SD/sd_card_cmd.v`、`SD/spi_master.v`、`SD/sdram.v`、HDMI加密IP、PLL、引脚约束和时序约束。读取它们用于核对硬件与底层接口；复用范围仍受上面的规则边界约束。

旧.al内部含原电脑绝对项目路径，新机打开时检查项目定位和所有相对源引用；不要把它改个名当作新整机工程。旧ex4记录的SWNS=-6.565ns、HWNS=0.049ns，违例尚未解决，旧bitgen成功不代表时序通过。

实际板上按键映射：KEY2手动下一张，KEY4自动轮播切换，KEY1复位；必须结合`pin.adc`和板卡丝印复核。数码管还受DIG/LED选择开关影响。PROGRAM_SRAM断电丢失，Flash冷启动需独立验收。

## 7. 未完成工作与协作约束

剩余工程清单见`NEXT_TASKS.md`。下一步是512字节真实扇区适配与启动加载调度，然后真实SDRAM回应/显示读取、交互与像素处理、新TD整机，最后接自主音频并做整机稳定性与冷启动验收。音频此前被用户暂缓；图片链路接稳后再推进，最终100%必须包含音频。

保留原例程及队友文件；不要改写已发布历史。基于此交接提交建立接续分支，小步提交，逐轮报告实际证据、未完成项和整体进度。硬件现象由持板队友提供记录；harness不能用仿真日志虚构上板结果。

不向物理卡自动写扇区、不自动格式化卡、不在缺少器材确认时下载到板卡。既往提到的9032扇区测试与卡文件系统健康没有完成核验；当前代码只读，不需要重做原始扇区写测试。
