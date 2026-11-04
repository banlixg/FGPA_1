# 开机动画、开机音效与音量 OSD（2026-11-04）

本文件说明 2026-11-04 新增的三项功能，以及它们与既有链路的关系。全部改动均为**加法式**，不破坏原四图/切图/淡入淡出/音频链路。

## 1. 上电到出图的完整时序

```
上电
 └─ 0 ~ 10 s   开机动画 + 10 秒开机音效
                画面：呼吸光点 → 24 点圆环逐个点亮 → 彗尾旋转 + 进度条 → 闪白 → 转黑
                声音：自建 DDS 合成（上升扫频 C4→C6 + C3 铺底 → C5-E5-G5-C6 琶音 → C6 延音 → 收尾和弦）
 └─ 约 10 s    「识别图片中」+ 下方 8 点转圈；**同时开始读卡装图**
                数码管（从右数第 2 位 = 已驻留图片数）0 → 1 → 2 → 3 → 4
 └─ 装图完成   立即切换到实时图片
                屏幕：红底 TEAM FRAME 01（四张依次 红/绿/蓝/紫）
                声音：切到 AUDIO.WAV 循环
                数码管：0 4 0 1 4 5
```

**顺序是硬保证，不是靠延时**：
`team_player_core` 里 `boot_start = sd_initialized && mem_initialized && 动画结束(anim_done) && !boot_started`，
即动画播完前 `team_boot_loader` 根本不会启动，因此"先动画、再读图"不会被 SD 卡速度打乱。

## 2. 显示层结构（视频域）

```
team_line_scanout（帧区行读取 + 视频时序）
        │ raw_rgb / raw_de / raw_hs / raw_vs / raw_x / raw_y
        ▼
team_boot_layer（三层合成，输出晚 1 拍）
        │  PH_BOOT 动画  /  PH_LOAD 「识别图片中」+转圈  /  PH_IMG 透传
        ▼
team_fade_effect（淡入淡出，x/y 已对齐打 1 拍）
        ▼
team_volume_osd（音量竖条叠加，只改 rgb）
        ▼
HDMI 发送核
```

- `team_boot_layer.v`：动画与加载画面渲染器；`o_boot_done` 同时作为 `boot_loader` 的启动门控。
- `team_boot_font_rom.v`：64×64 汉字点阵 ROM（"识别图片中"，5 字），只为加载画面服务。
- `team_volume_osd.v`：音量调节 + 竖条绘制（见第 4 节）。

## 3. 音频结构

```
team_audio_file（WAV 解析，存储域）→ team_pcm_fifo → team_pcm_hdmi → 音频输出
team_boot_chime（自建 DDS 音效，视频域 48kHz 节拍）─┐
                                                  ├─ 按 boot_done 二选一
                                                  ▼
                                     audio_valid / audio_left / audio_right
```

- 开机音效在 `boot_done` 之前输出，之后自动切回文件 PCM，两者不会重叠。
- 视频域用 25 MHz 累加器生成 48 kHz 节拍（`48000/25000000`），供音效取样与动画层看门狗使用。

## 4. 音量 OSD（本机音量）

### 为什么不做"白板音量键"

- 白板（HDMI 显示器/一体机）的音量键作用在**它自己的功放**，音频经 HDMI 送到白板后才被放大/衰减；
- 本板**输出口 HDMI B 没有 CEC 连线**（手册引脚表只有 `HDMIA_CEC`，且当前设计输出走 HDMI B），
  FPGA 既收不到按键事件，也无法读取白板音量值；
- 因此音量可视化做在**本机数字增益**上：竖条 = 本机增益，白板音量键仍可调总响度（白板自身行为）。

### 操作与表现

| 操作 | 效果 |
|---|---|
| SW1（C8）拨动一次 | 音量 +1 级（0~15） |
| SW2（C7）拨动一次 | 音量 −1 级 |
| 任意调节 | 屏幕右侧弹出竖条，停止拨动约 2 秒后自动隐藏 |

- 竖条位置：`x = 588..612`，`y = 140..340`（右侧安全区，不遮挡画面主体）
- 外观：白色外框 + 内部填充；音量 <5 橙色、5~9 黄色、≥10 绿色；音量 0 只显示空框
- 默认音量 10/15
- 数字增益：`out = pcm × level / 16`（24 位有符号，`>>4`），相邻级差约 0.4 dB~6 dB

## 5. 按键最终分配

| 板载丝印 | FPGA 引脚 | 功能 |
|---|---|---|
| KEY1 | A2 | 整机复位（重新开始动画与加载） |
| KEY2 | B2 | 下一张（带淡入淡出，动画忙时请求合并） |
| **KEY3** | B1 | **自动轮播开/关**；开启时若原为 10s 档自动回到 5s 档 |
| **KEY4** | C1 | **轮播间隔 2s ↔ 5s 切换**，仅在自动轮播开启时有效 |
| SW1 | C8 | 音量 +1 |
| SW2 | C7 | 音量 −1 |

> 说明：`team_player_control` 的端口名沿用旧设计（`auto_key_n` / `period_key_n`），
> 但功能含义已按要求交换，代码注释已同步更新。

## 6. 资源与时序（2026-11-04 最终版）

| 项 | 值 |
|---|---|
| LUT / MSlice | 见 `records/td_*` 的最终 `team_player_phy.area` |
| BRAM | 含 HDMI IP + 字模 ROM + 帧区行 RAM |
| 时序 | **SWNS +2.503 ns / HWNS +0.024 ns**（0 违反，`board/timing.sdc` 含 SDRAM 源同步例外说明） |
| 最终 bit | `team_player.bit`，SHA256 见 `release` 或交付包 |

## 7. 复现

```powershell
cd board
td_commands_prompt.exe build.tcl     # 产出 team_player.bit
svfgen -chip EG4S20BG256 -bit team_player.bit -svf flash.svf `
       -scan_mode prog_spi -start_addr 0x0 -flash W25Q16JV
program_svf -svf flash.svf -spd 8
download -mode verify_spi -bit team_player.bit -start_addr 0x0
# 断电 -> 上电；板上 DIG/LED 开关拨到"数码管"位
```

TF 卡根目录：4 个 `IMG0001..4.BMP`（640×480/24bit）+ `AUDIO.WAV`（48kHz/16bit/stereo）。
