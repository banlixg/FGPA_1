# 板测记录 2026-11-03（接续 candidate_01）

接手提交：`ba5b22103c69071c884819f70e2ab10ff3054625`（`integration/full-player`，进度 90）。
本记录只包含**可自动核对的事实**，人工观察结果待补（`board_verified` 仍为 false）。

## 1. 候选包完整性

```
python tools/verify_candidate.py
CANDIDATE_PASS files=431
Board verified: False   Progress: 90
Bit SHA256: 4a89f61f15492fdf9dde9bc7063b1c192598753171c1135f78c370ad424e05fa
```

- 本地解压路径：`D:\FPGA_Competition\repo_FGPA_1\_branch\FGPA_1-ba5b22103c69071c884819f70e2ab10ff3054625`
- 实测 `release/2026-10-26_candidate_01/team_player.bit` 的 SHA256 =
  `4a89f61f15492fdf9dde9bc7063b1c192598753171c1135f78c370ad424e05fa`，与清单一致。
- `BUILD_AND_TEST.json`：SWNS +0.810 ns、HWNS +0.022 ns、138 项回归、`board_verified=false`。

## 2. 素材核对（release/2026-10-26_candidate_01/media）

| 文件 | 规格 | 实测 |
|---|---|---|
| IMG0001..0004.BMP | 640×480、24 位、921654 B | ✅ Pillow 打开为 RGB 640×480，字节数一致 |
| AUDIO.WAV | 48 kHz / 16 位 / 双声道 / 4 s | ✅ wave 读取：ch=2, width=2, rate=48000, 192000 帧 = 4.00 s |

预期画面（`预期四图.png`）：四张底色分别为红/绿/蓝/紫，图上文字
`TEAM FRAME 01..04`、`TOP LEFT`、向上箭头、`BOTTOM / KEY2 NEXT / KEY4 AUTO`，
色条顺序为 红、绿、蓝、黄、青、品红、白、黑。

## 3. 本次执行：SRAM 临时下载

| 项 | 值 |
|---|---|
| 板卡 | `Anlogic usb cable v0.1` 在线 |
| 器件 | `read_device_id` → `EG4S20BG256` |
| 命令 | `download -mode jtag -bit .../release/2026-10-26_candidate_01/team_player.bit` |
| 结果 | `PRG-2014 Chip validation success` → **PROGRAM OK**（6.5 s） |
| 日志 | 同目录 `program_sram.log` |
| 注意 | SRAM 掉电丢失，重新上电需重新下载本 bit；Flash 冷启动留到图像/声音确认后再做 |

## 4. 待人工填写的观察项

见 `docs/板上验收_2026-10-26.md` 第 4~6 节：四图/方向/颜色、淡出淡入、KEY2 十次切换、
KEY4 轮播开关、KEY3 三档周期、HDMI 旋律、数码管 6 位读数、异常出现时机。
数码管位定义：位5 启动阶段、位4 驻留张数、位3 当前帧号、位2 模式、位1 音频状态、
位0 优先错误（0 无 / B HDMI 未就绪 / C 音频欠载 / D 行欠读 / E 淡入淡出故障 / F 图片不足）。

## 5. TF 卡准备（2026-11-03 20:2x，E:）

- 卡：`E:` 14.56 GB，FAT32，卷标 `ZL31`，剩余约 14.9 GB。
- 旧素材（原根目录，均为 640×480/24bit/921654 B）**移动**到 `E:\_backup_20261103\`（未删除、未覆盖）：
  `西瓜_640x480_24bit_显示正常_工程适配版.bmp`、`苹果_640x480_24bit_显示正常_工程适配版.bmp`、
  `test03_640x480_24bit.bmp`、`logo_640x480_24bit_不翻转.bmp`。
  原因：程序只枚举根目录且会拿前 4 张合格 BMP，旧图会被当候选，必须先移走。
- 复制候选素材到根目录，并逐文件核对 `MEDIA_MANIFEST.json` 的 SHA256：

| 文件 | 字节 | SHA256 |
|---|---:|---|
| IMG0001.BMP | 921654 | ee4b7e70… OK |
| IMG0002.BMP | 921654 | 8bbf08c7… OK |
| IMG0003.BMP | 921654 | b20b7052… OK |
| IMG0004.BMP | 921654 | 6dcf53c1… OK |
| AUDIO.WAV | 768044 | 9e3f8a6d… OK |

- 复制后根目录：`AUDIO.WAV`、`IMG0001..0004.BMP`、`System Volume Information`、`_backup_20261103`。
- 已 `Write-VolumeCache -DriveLetter E` 刷新缓存，可安全弹出。
- 下一步：断电 → 卡插回板子 → 上电 → 重新下载 `team_player.bit`（SRAM 掉电会丢）。

## 6. 第二次 SRAM 下载（插卡上电后）

- 时序：卡准备完成 → 板子断电 → 插卡 → 上电（2026-11-03 20:2x）
- `Anlogic usb cable v0.1` 在线，`read_device_id` → `EG4S20BG256`
- `download -mode jtag -bit .../team_player.bit` → `PRG-2014 Chip validation success` → **PROGRAM OK**（6.5 s）
- 日志：`program_sram_after_card_insert.log`
- 状态：等待人工观察（四图/方向/颜色/淡入淡出/按键/旋律/数码管），`board_verified` 仍为 false
