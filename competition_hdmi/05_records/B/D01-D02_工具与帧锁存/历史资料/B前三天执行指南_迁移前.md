# B 的前三天执行指南

按个人从头开始安排：第1天做原手册D01—D02，第2天做D03—D04，第3天做D05—D06。若2026-10-06开始，对应10月6、7、8日；这不是要求重做团队已完成的任务。你自己仍应能复跑一次关键检查。每一天预计2—3小时，首次安装、调试或卡故障可能增加时间。

你的职责是让团队拿到可验证的BMP素材、可复跑的独立模型、真实的TF卡测试记录。完整工程由C集成。前三天完成后，你应能说明“图片合不合格、实际读出哪些图、模型什么时候更新编号”。真实帧交接、跨时钟域状态传递在后面的D09之后展开。

**已经替你准备和验证的内容**

- `03_sim/B_frame/src`：帧编号锁存练习模块和自检testbench。
- `03_sim/B_frame/sim/run.do`：ModelSim10.4脚本。本机10项检查通过；故意错误能返回失败。
- `04_assets/tools`：只读BMP检查工具、四张测试图生成工具。Python标准库即可，不需要安装Pillow。
- `04_assets/official/official_watermelon.bmp`：从本机官方资料包原样复制的西瓜图；原始路径见同目录SOURCE.txt。
- `04_assets/numbered/01.bmp`至`04.bmp`：640×480、24位、压缩0的编号图，四角颜色和边框已检查。
- `04_assets/negative_examples/bad_320x480.bmp`：故意不符合工程尺寸的离线练习样本，放在独立目录。
- `05_records`：本次电脑验证日志。这些日志属于本次辅助准备，不能冒充你个人复跑或板上结果。

板上显示方向、TF卡布局、实际图序、按键、HDMI声音均未测。本包没有运行TD完整实现，没有下载配置，没有操作任何TF盘。

**路径约定和第一次放置文件**

统一工作目录W：`D:\FPGA FILE\competition_hdmi`。沿用原手册。路径有空格时，下面的ModelSim命令用花括号，PowerShell命令用引号。

1. 解压本包后，找到包含本指南、00_team、03_sim、04_assets、05_records的那一层。
2. 在资源管理器建立W，将以上四个目录及指南复制到W。已有同名文件时先比对保留，不整包覆盖队友成果。
3. W下另外建立`01_baseline`、`02_develop`、`06_submission`。C已有团队目录时直接使用已有结构。
4. VS Code → 文件 → 打开文件夹 → 选择W。通过资源管理器“查看→显示→文件扩展名”确认`.v`和`.py`没有变成`.txt`。

本机核实存在的资料目录是：

```text
D:\FPGA FILE\HX4S20_Contest_202606\7_lab_ex_2026_nosoft\全国大学生嵌入式芯片与系统设计竞赛'2026选题指南_康芯
```

其中的单引号是目录名的一部分。直接在资源管理器逐层进入即可。

## 第1天：建立副本，亲手跑一次小仿真

**1. 复制两个完整例程，约30—45分钟。**

从上述资料目录分别复制整个`lab_ex4_tf`和`lab_ex5_i2s`到`W\01_baseline`。不要只复制顶层v文件。打开副本检查以下文件能找到：

| 检查项 | ex4相对路径 | ex5相对路径 |
|---|---|---|
| TD工程入口 | src/td_project/lab_ex5_i2s_v1.0.al | src/td_project/HDMI1.4b_Transmitter_v1.0.al |
| 顶层 | src/user_source/hdl_source/top_tf_hdmi_audio.v | 同左 |
| 引脚约束 | src/user_source/constraints_source/pin.adc | 同左 |
| 时序约束 | src/user_source/constraints_source/timing.sdc | 同左 |
| 读图源 | src/user_source/hdl_source/SD/bmp_read.v | 同左 |
| 素材和说明 | doc/TF卡图片、doc/convert | 同左 |

ex4工程文件名里出现ex5是这份资料的实际命名，按所在文件夹辨别。保留include、IP、ROM及原来的相对层级。原包里的旧bit只能说明资料附带了生成物，本机实现由C另行验证。

**2. 填素材清单，约15分钟。**

打开`00_team/B_素材清单.md`，填你的TF卡容量/卷标/读卡器情况、谁持板、准备首测的官方BMP。硬件不在手写“未到手”；板上项写“未测”。素材文件可打开与能上板显示是不同记录。

**3. 理解锁存练习，约20分钟。**

打开`03_sim/B_frame/src/team_frame_latch.v`。只需先看懂下表，不必在第一天学习完整SDRAM或HDMI协议。

| 信号 | 作用 |
|---|---|
| clk | 练习时钟，testbench每20ns一周期，即50MHz |
| rst_n | 0时复位，1时正常运行 |
| frame_id_in[1:0] | 本次准备采纳的编号，0—3；以后可对应屏幕01—04 |
| frame_accept | 时钟上升沿为1才采纳输入编号 |
| frame_id_out[1:0] | 已采纳编号，没有事件就保持 |
| frame_valid | 表示已经采纳过有效编号，避免把复位值误认作首图 |
| accepted_pulse | 本拍是否采纳；连续两个有效事务时可连续两拍为1 |

一次输入事件持续一个时钟周期。这个模型不从卡读图，也不确认真实画面已上屏；它练的是“输入改变不等于输出立即改变，更新需要明确事件”。练习时钟不代表完整工程所有模块的实际频率。

**4. 在ModelSim运行，约30—45分钟。**

打开本机ModelSim SE-64 10.4。若已有仿真，先结束当前simulation。在底部Transcript逐行输入：

```tcl
cd {D:/FPGA FILE/competition_hdmi/03_sim/B_frame/sim}
do run.do
```

本脚本自行创建work库并编译，不必先建GUI工程。它需要从上面的sim目录启动，避免相对路径指向上一任务。成功末尾应包含：

```text
ALL_PASS checks=10
SCRIPT_PASS: ALL_PASS checks=10
```

Wave窗口会显示7个主要信号。没有Wave窗口时通过View→Wave打开。编号信号用Unsigned/Decimal查看；观察时钟上升沿，输出应在该沿完成采纳。

| 要看懂的现象 | 预期 |
|---|---|
| 复位 | 编号0、valid0、采纳标志0 |
| 没有事件，输入编号改成3 | 输出仍为0，valid仍为0 |
| 有事件，输入1 | 输出变1，valid变1 |
| 没有事件，输入改2 | 输出仍为1，采纳标志回0 |
| 相邻两拍分别采纳2和3 | 输出分别变2和3 |
| 再次复位 | 编号和标志重新清零 |

首次还要验证一次“测试真的能发现错误”：

```tcl
set INJECT_FAIL 1
do run.do
```

这次故意把最后一个预期编号写错，应显示`TEST_FAIL`。然后恢复并复跑：

```tcl
set INJECT_FAIL 0
do run.do
```

恢复后重新出现ALL_PASS，保存最终正确的transcript.log、result.txt和一张能看到“有事件更新/无事件保持”的波形截图。你自己执行后的日志才是你的个人运行证据。

**当天完成标准：**两个完整官方副本可打开；素材清单有真实设备状态；你能自己启动脚本、读出上述波形，并保存正确日志。交给C的是RTL、tb、run.do、截图和一句“练习模型尚未接卡、内存、像素链路”。

## 第2天：检查官方图，建立四张诊断素材

**1. 检查首测官方图，约20分钟。**

VS Code → 终端 → 新建终端，确认是PowerShell。在W下运行：

```powershell
Set-Location -LiteralPath "D:\FPGA FILE\competition_hdmi"
python .\04_assets\tools\check_bmp.py .\04_assets\official --json .\05_records\B_official_check.json
```

本机python位于C:\Python314\python.exe。终端若未识别python，可用`& "C:\Python314\python.exe"`替代命令开头的python。脚本不修改输入BMP；`--json`只是指定检查报告保存位置。

标准输出字段：

| 字段 | 本包图像 | 理解方式 |
|---|---|---|
| signature | BM | 文件真的是BMP，不靠后缀判断 |
| width、height | 640、+480 | 这份读图工程要求的尺寸与高度方向 |
| bpp | 24 | 每像素R/G/B三个8位通道 |
| compression | 0 | 无压缩 |
| pixel_offset | 54 | 本包像素数据从第54字节开始 |
| actual_bytes | 921654 | 本包54字节头＋921600字节像素 |

像素量为640×480×3=921600字节。54字节偏移是本包和所选官方图的值，并非所有合法BMP必须如此。检查脚本会读取实际偏移，核对头、文件长度及像素区域。BMP通常正高度表示自底向上存储，这份工程的方向是否正确仍以四角图上板实测为准。

**2. 用错误尺寸图做拒绝测试，约10分钟。**

```powershell
python .\04_assets\tools\check_bmp.py .\04_assets\negative_examples\bad_320x480.bmp
```

出现FAIL以及`Width must be 640`是这次的正确结果。该图保留在negative_examples，不放进numbered，不拷到TF卡。然后重跑官方合格图确认OFFLINE_PASS。

**3. 生成并检查编号图，约30分钟。**

本包已经提供四张图。你可打开查看，也可亲手在新目录生成一遍：

```powershell
python .\04_assets\tools\make_numbered_bmp.py --out .\04_assets\numbered_my_run
python .\04_assets\tools\check_bmp.py .\04_assets\numbered_my_run --json .\05_records\B_numbered_check.json
```

若想保留本包numbered作为团队正式素材，也应亲手运行：

```powershell
python .\04_assets\tools\check_bmp.py .\04_assets\numbered --json .\05_records\B_numbered_check.json
```

生成工具发现同名文件会停止，避免覆盖你已经登记的素材。你确定要重新生成时才使用`--overwrite`。工具只写指定素材目录，没有卡盘符参数。

查看四张图应看到：中心01—04；左上红、右上绿、左下蓝、右下黄；白色细边框；顶部TOP、底部BOTTOM。编号判图序，四角和文字判方向，色块判通道顺序，边框判裁切。图的编号是我们画进像素的文字，并非FPGA按文件名产生的编号。

如果以后要转换照片，使用官方`doc/convert/convert_images_to_bmp.py`的明确单文件输入输出方式，并再次运行本检查工具。保留“原图→转换图”路径；JPG直接改后缀无效。首次上板依旧先用官方自带单图。

**4. 登记清单和交付，约20—30分钟。**

在`B_素材清单.md`记录官方图＋四张编号图的路径、来源、尺寸、位深、压缩、报告位置。图序填“待上板”，不填想象中的01→02→03→04。通过JSON报告中的sha256可确认交付文件是否和检查时一致。

C同时负责ex4完整实现。你交给C：合格官方图、四张编号图、检查工具、JSON结果、素材清单和错误样本拒绝结论。约定先官方单图，再两张，最后四张；让C准备对应本机源码的新配置文件。

**当天完成标准：**合格图能被接受，320宽错误样本能被拒绝；四张诊断图都通过；清单可让队友找到准确文件。你能说明为何“电脑能打开”仍不足以证明适配例程。

## 第3天：做单图与多图实测，登记真实卡行为

**有板、有卡、有C生成的ex4配置时，按以下顺序。**

1. 持卡者先备份专用TF卡，在资源管理器核对实际盘符、容量、卷标。盘符由当时实物确认，本指南不预设E盘。需要格式化时由持卡者对核实后的专用卡操作，并登记方式。快速格式化与普通删除不能保证物理旧BMP残留消失。
2. 首轮只放`official_watermelon.bmp`到卡根目录；安全弹出。板卡断电插卡，HDMI_B连接带HDMI输入的屏幕。C下载本机新生成ex4配置，先用Program SRAM临时验证。
3. 你登记卡条件、所用BMP、配置文件路径、首次出图结果。A看方向/颜色/边缘，C保存下载日志。仅显示正确官方首图时填“单图通过”。
4. 单图通过后，按原手册F3在专用卡准备两张编号图01、02，保留单图回退素材与记录。不要以为资源管理器只剩两张就保证板只会扫描到两张。确认真实只发现这两张后，A/C操作KEY1，你每按一次登记实际屏幕编号。
5. 两张稳定后再准备01—04，实测首图、KEY1顺序及绕回。比如实际出现03→01→04→02→03，就照实记录。出现第5张旧图或缺图时，记录旧图/缺图异常，停止把当前卡称为四图通过。
6. A/C用KEY2测试进入自动和回到手动，你记录实际可见图号、持续黑屏/半图/旧图情况。此时测的是官方原样行为，2/5/10秒档和长短按尚未实现。
7. 选择每个有代表性的画面保存照片，填写`05_records/B_板上测试表.md`。测试时间、卡、配置、实际顺序必须能对应。

这份代码不按FAT目录中的文件名寻找图片：`sd_card_bmp.v`给`bmp_read.v`的扫描范围是扇区0—131071，共131072×512字节，约64MiB。按物理位置寻找BM和图像头，匹配图后按文件长度向后跳。文件起点、连续存放和扫描窗口都可能影响识别。

因此文件名01、02只方便人管理，实际显示顺序以屏幕中心编号为准；新图复制成功也可能落在扫描窗口外；旧图文件被删除后数据头可能还在。出现这些问题时，保存现象、恢复已验证卡/素材，并结合扫描与卡布局定位，不能反复快速格式化后直接宣布“彻底清干净”。官方sync_to_sd.py涉及删除目标卷内容和修改BMP头，不列入这三天的默认操作。

**看懂读图路径，约30—45分钟。**

VS Code打开自己ex4副本中的：

```text
src/user_source/hdl_source/SD/bmp_read.v
src/user_source/hdl_source/SD/sd_card_bmp.v
src/user_source/hdl_source/top_tf_hdmi_audio.v
```

Ctrl+F分别搜索：

- bmp_read.v：`header_match`、`pixel_offset`、`file_len`、`bmp_data_wr_en`。
- sd_card_bmp.v：`SCAN_MAX_SECTOR`、`bmp_ready`、`source_done_seen`、`write_finish_pulse`、`disp_buf_idx`。
- 顶层：`frame_write_toggle_mem`、`sd_card_bmp_m0`、`video_delay`、`I_rgb`。

先能回答：从卡读来的三个字节如何组成像素？数据送完后为什么还要等写帧完成？显示缓存选择是谁更新？屏幕真正显示新图还要经过哪些读帧和像素路径？不要在第三天直接重写这些模块。

这一版官方存储模块参数CLK_FREQ_HZ为100_000_000，后续设计必须根据真实时钟连线核对，不能把练习50MHz或润色版概述当实际所有时钟。缓存号也是存储地址身份，不等于BMP文件名或中心图号。

可以把下面文字与这三个真实文件一起交给AI解释：

```text
我是B，现在只读官方ex4，不修改工程。
请依据我提供的bmp_read.v、sd_card_bmp.v和top_tf_hdmi_audio.v，
从TF扇区字节追踪到像素数据写入，再到显示缓存与视频输出。
先解释header_match、pixel_offset、file_len、bmp_ready、source_done_seen、
write_finish_pulse、disp_buf_idx的实际意义，给出实例连接依据。
标明各时钟/复位及仍需继续追踪的读帧模块。
不要把源读取结束、整帧写完、读端采纳、可见像素输出混成一个完成事件。
不假定现有scene_visible端口，不编写底层补丁。
```

**没有板或暂时没有卡时，第三天改做以下电脑项。**

- 检查单图、两图、四图清单，保留合格集合；完成错误样本拒绝测试。
- 打开上述三个文件，填`00_team/B_读图路径.md`，说明扫描范围及四个不同阶段。
- 把板上动作表交给实际持板者，让对方以后按表记录。
- 明确登记“电脑项完成，板上未测”；板到后先补官方单图。

板上故障或C的ex4实现未通过时，不强行推进多图。你可以完成源码追踪和离线素材检查，保留物理项等待补测。

**当天完成标准：**有板则留下单图及实际进行的多图结果，不通过项有条件、现象和证据；无板则离线集合与源码路径文档完整、板上栏仍写未测。C可用你的材料复现测试，不需要再猜用了哪张图哪块卡。

## 遇到问题时怎么继续

| 现象 | 先检查 |
|---|---|
| 找不到run.do | ModelSim是否先cd到B_frame/sim；是否保存成run.do.txt |
| 找不到v文件 | src/sim是否并列，是否解压后多套了一层目录 |
| 编译通过但无ALL_PASS | 是否加载tb_team_frame_latch；从第一条错误定位 |
| 编号全X | clk、rst_n是否在tb中驱动，是否启动了tb而不是裸RTL |
| 故意错误后一直FAIL | `set INJECT_FAIL 0`后重新do run.do |
| Python无输出一闪而过 | 用VS Code终端运行，不用双击脚本 |
| BMP FAIL | 按ERROR字段修尺寸、位深、压缩或长度，再检查 |
| 板上显示旧图/缺图 | 保存卡条件和现象，查物理扫描及布局，不按资源管理器推断 |
| 板上黑屏 | 与A/C核对供电、输入源、HDMI_B、卡、实际下载文件 |

给AI提供“正在做第几天哪一步＋第一条完整错误＋相关文件＋实际输入＋预期/实际差异”。约30分钟仍未定位时先保存问题，继续当天独立项目，完整工程由C保留最后通过版本。

**参考依据**

原手册2026-10-04版D01—D06、F1/F3及分工表；本机资料包ex4实际源码和convert README。BMP字段与行存储含义参考[Microsoft BITMAPINFOHEADER文档](https://learn.microsoft.com/windows/win32/api/wingdi/ns-wingdi-bitmapinfoheader)。这份指南按当前用户请求安排B的前三天，没有执行文档中报名、发送、固化或提交动作。
