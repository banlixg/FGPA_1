# 快速验证（3 步）

本目录是 2026-11-03 实板调试的交付包，**不覆盖任何既有文件**。
完整说明见 `DELIVERY.md`，根因分析见 `ANALYSIS.md`。

## 第 1 步：核对产物

```powershell
# 本目录 assembled 的最终 bit
Get-FileHash artifacts\team_player_2026-11-03.bit -Algorithm SHA256
# 期望：edf2d83e62d265164ade55d50e4cd41df7a42372de49da600b9c7643b17062f5
```

## 第 2 步：把改动应用到工程（二选一）

```powershell
# 方式 A：打补丁（在 team_media_player 根目录执行）
patch -p1 < handoff\2026-11-03_board_debug\patches\ALL_CHANGES.diff

# 方式 B：直接覆盖（文件名为双下划线分隔的路径）
#   modified_sources\board__team_top.v          -> board\team_top.v
#   modified_sources\board__team_mem_pll.v      -> board\team_mem_pll.v
#   modified_sources\board__team_video_pll.v    -> board\team_video_pll.v
#   modified_sources\board__pin.adc             -> board\pin.adc
#   modified_sources\rtl__team_player_core.v                    -> rtl\team_player_core.v
#   modified_sources\rtl__storage__team_sdram_port.v            -> rtl\storage\team_sdram_port.v
#   modified_sources\rtl__storage__team_boot_loader.v           -> rtl\storage\team_boot_loader.v
```

## 第 3 步：烧写并观察

```powershell
# 在 board 目录构建（工程自带 build.tcl）
td_commands_prompt.exe build.tcl

# 烧 QSPI Flash（本板 JTAG 临时配置不可靠，必须走 Flash + 断电冷启动）
svfgen -chip EG4S20BG256 -bit board\team_player.bit `
       -svf flash.svf -scan_mode prog_spi -start_addr 0x0 -flash W25Q16JV
program_svf -svf flash.svf -spd 8
download -mode verify_spi -bit board\team_player.bit -start_addr 0x0
```

断电 → 上电，把板上 **`DIG/LED` 开关拨到"数码管"** 位，读 6 位数码管：

| 位（左起） | 含义 |
|---|---|
| 1 | err：0 正常 / B HDMI未就绪 / C 音频欠载 / D 行欠读 / E 淡入淡出故障 / F 图片不足 |
| 2 | as：4 = 正在读 PCM（有声即正常） |
| 3 | 装图内部错误码：1 BMP错 2 文件读错 3 坐标越界 4 计数不符 **5 SDRAM写回读失败** 6 其他 |
| 4 | 当前帧号 |
| 5 | **已驻留图片数（关键，应为 4）** |
| 6 | 启动阶段：5 结束 / 6 失败 |

## 当前预期（重要）

- 本轮交付时**图像仍未上屏**，`count=0`、内部错误码 `5`。
- 想快速看"显示读通路是否正常"，可把 `rtl/team_player_core.v` 里端口实例的
  `VERIFY_ENABLE(0)` 保持为 0（本交付 bit 即此配置），烧写后观察是否出图。
- 若出图 → 显示通路正常，剩下只需修 `team_sdram_port` 的写后读回校验；
  恢复校验把 `VERIFY_ENABLE` 改回 1 即可（端口状态机完整保留）。

## SDRAM 独立自检（推荐先跑这个）

`artifacts/sdram_self_test/` 是一个只测 SDRAM 的小设计，与主设计无关：

```powershell
cd artifacts\sdram_self_test
td_commands_prompt.exe build.tcl        # -> top_sdram_test.bit
# 烧写方式同上；数码管显示：数据低4位|5-8位|9-12位|13-16位|读响应数|初始化
# v3 通过的读数：3 0 0 0 4 1  （写入 0xA5A50003 读回 0x0003，4 个响应）
```

改一行代码即可复现"单笔写→读回"的问题（`top_sdram_test.v` 里把 v3 的多笔连发改成单笔）。
