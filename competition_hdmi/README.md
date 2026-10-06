# 安路选题一 · 三人共享工作区

赛题：基于EG4S20的HDMI多媒体播放系统。平台：HX4S20C / EG4S20BG256。

本机统一工作目录：`D:\FPGA FILE\FPGA_1\FGPA_1\competition_hdmi`。克隆仓库后，以仓库内`competition_hdmi`为工作目录W；脚本尽量使用相对路径，各电脑不要求盘符相同。

| 角色 | 负责内容 | 当前已确认状态 |
|---|---|---|
| A 显示与交互 | 像素、OSD、可见标记、亮度 | 本目录尚未收到A的新交付；待填写 |
| B 图片与存储 | BMP素材、帧身份、显示确认、存储接口 | D01-D02帧锁存个人复跑通过并有截图；D03-D04四张图已由B确认内容，离线复核通过 |
| C 控制、音频、集成 | 按键、调度、音频、顶层、TD、版本发布 | 本目录尚未收到C的构建报告；待填写 |

## 文件入口

| 目录 | 用途 |
|---|---|
| 00_team | 三人共同约定、进度、个人操作指南和每日记录 |
| 01_baseline | 完整官方参考例程；内部层级保留。附带旧生成物不代表本队已验证 |
| 02_develop | C维护唯一集成工程；基线验证后再初始化 |
| 03_sim/A、B、C | 各自模块源码、testbench和运行脚本，按D任务范围分层 |
| 04_assets | 团队使用的官方图、B的编号图/错误样本/工具 |
| 05_records/A、B、C | 个人工作证据，先按角色，再按Dxx-Dxx，再按日期或证据类别 |
| 05_records/TEAM | 全队版本V00/V01/RC01、整机回归与发布记录 |
| 06_submission | 冻结后正式提交材料，目前待准备 |

B素材报告：`05_records/B/D03-D04_素材检查/B_D03-D04_素材检查报告.md`。

B本人仿真与截图：`05_records/B/D01-D02_工具与帧锁存/本人复跑/2026-10-06/`。

B当前仿真源码：`03_sim/B/D01-D02/B_frame/`。迁移后重新打开ModelSim，在Transcript运行：

```tcl
cd {D:/FPGA FILE/FPGA_1/FGPA_1/competition_hdmi/03_sim/B/D01-D02/B_frame/sim}
set INJECT_FAIL 0
do run.do
```

通过标准：`ALL_PASS checks=10`和`SCRIPT_PASS`。这个练习模型尚未接入真实TF/SDRAM/HDMI。

## 同步与保留

运行缓存、ModelSim本机库配置、官方附带TD运行目录与旧工具日志在本机保留，由本工作区.gitignore排除；个人已归档的证据和硬件源文件正常提交。两份官方大视频通过Git LFS同步；首次克隆需Git LFS和`git lfs pull`取得视频本体。

仓库原有`A_WORK`和`B work`作为以前的学习记录保留。本队比赛工程统一从本目录进入。

目前没有登记板上单图、多图、音频、冷启动或整机基线通过；待实际持板者补证据。
