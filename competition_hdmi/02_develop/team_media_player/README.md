# 自主架构 HDMI 媒体播放器

更新：2026-10-26。**整体进度90/100，等待新工程实板验收。**

- [先看板上操作教程](docs/板上验收_2026-10-26.md)
- [进度与证据](PROGRESS.md)
- [与ex4/ex5的实质差异](docs/自主实现差异_2026-10-26.md)
- [时钟、跨域和限制](docs/CDC与时钟审查.md)
- TD工程：`board/team_player.al`；顶层`team_top`；芯片`EG4S20BG256`。
- 候选bit与测试素材：`release/2026-10-26_candidate_01/`。

## 已接成的数据通路

TF只读SPI及512字节缓存 → FAT32目录与簇链 → 自主BMP解析 → 写后读回验证 → 四图驻留SDRAM → 两行交替预取 → 帧边界切图和淡出/淡入 → HDMI。

图片驻留后，TF通路读取WAV文件，经过自主RIFF解析、PCM异步FIFO和48 kHz节拍输出HDMI音频。默认背景WAV持续循环，未实现每图独立配音轨。

KEY2下一张，KEY4自动轮播开关，KEY3切换约2/5/10秒周期，KEY1复位。只扫描根目录，至少准备4张640×480、24位无压缩BMP；音频准备48 kHz、16位PCM单/双声道WAV，优先`AUDIO.WAV`。

## 已验证与尚未验证

五套回归共138项通过；含四张完整分辨率图的加载、5,529,600个显示像素核对、实际接入淡入淡出的整机联测和文件PCM循环播放。TD完成实现和bit生成，现有约束下布线后建立/保持裕量均为正。具体SHA、报告路径以候选包清单和PROGRESS为准。

**这不是本板已播放成功的结论。** 新bit尚未取得实卡/显示器/扬声器、持续稳定性与Flash冷启动结果。外部I/O完整时序、供应商SIP实例位置警告及最终规则复用边界仍需核实。原ex4的板测结果不移用为新工程结果。

## 复现

使用已有Python 3.10+、Pillow和Icarus安装，先切到本目录：

```powershell
python tools/run_bmp_regression.py --iverilog-bin <已有Icarus的bin目录>
python tools/run_fat32_regression.py --iverilog-bin <已有Icarus的bin目录>
python tools/run_frame_regression.py --iverilog-bin <已有Icarus的bin目录>
python extensions/fade/tools/run_fade_regression.py --iverilog-bin <已有Icarus的bin目录>
python tools/run_integration_regression.py --iverilog-bin <已有Icarus的bin目录>
python tools/build_board.py --td-bin <已有TD的td_commands_prompt.exe完整路径>
```

构建脚本在ASCII临时目录运行TD，再保存新证据；不安装软件、不更改系统配置、不读写实体TF卡、不下载板卡或写Flash。GUI打开工程前完整解压项目，避免中文目录造成TD兼容问题。已有vendor平台文件随工程保留，不必重跑`prepare_board_project.py`；该脚本用于从明确参考目录核对来源、重新生成平台配置。

旧45分交接文档已保存在`docs/history`。旧`HANDOFF_MANIFEST.json`只校验当时冻结包，不能作为本版更新后的源码门禁；本版用`CANDIDATE_MANIFEST.json`及`tools/verify_candidate.py`检查当前发布副本。
