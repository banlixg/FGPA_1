# 基于安路 EG4S20 的 HDMI 多媒体播放系统

HX4S20C V1.0 · EG4S20BG256 · Tang Dynasty 6.2

播放器从 FAT32 TF 卡读取四张 640×480、24 位 BMP 和 WAV 音频，经 SDRAM 帧缓存和 HDMI 输出。支持开机动画与 DDS 音效、淡入淡出、自动轮播及屏幕音量竖条。

## 构建与演示

1. 下载本分支并解压到英文路径，用 TD 打开 `board/team_player.al`，顶层为 `team_top`。命令行入口为 `board/build.tcl`，也可运行 `python tools/build_board.py --td-bin "<TD 程序路径>"`。
2. 将 `media/` 中的四张 BMP 和 `AUDIO.WAV` 复制到 FAT32 TF 卡根目录。
3. 插入 TF 卡、连接 HDMI，使用 `firmware/` 中的实板固件完成 QSPI Flash 配置，再上电播放。

| 操作 | 功能 |
|---|---|
| KEY1 | 复位 |
| KEY2 | 下一张 |
| KEY3 | 启停轮播 |
| KEY4 | 轮播时切换 2 秒／5 秒 |
| SW1／SW2 | 增加／降低音量 |

`rtl/` 和 `extensions/fade/rtl/` 包含应用逻辑，`board/vendor/` 包含平台 IP。实板版源自 `9dbb488`，固件校验值随文件提供。
