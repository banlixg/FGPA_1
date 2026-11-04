# 给持板队友的操作速查（SDRAM 优先）

> 目标：先把图像弄上屏，其余（按键/轮播/淡入淡出/稳定运行/冷启动）才可观察。
> 完整验收标准见同目录 `ACCEPTANCE.md`，根因分析见 `ANALYSIS.md`。

## A. 环境与前提（一次配好）

| 项 | 说明 |
|---|---|
| 工具 | TD 6.2.1（`td_commands_prompt.exe`），工程内自带 `board/build.tcl` |
| 烧写方式 | **必须 Flash + 断电冷启动**；本板 JTAG 临时配置报 OK 但不生效（已实测） |
| TF 卡 | 根目录只放 4 个 `IMG000x.BMP` + `AUDIO.WAV`，旧素材移到子目录 |
| 数码管 | 板上 `DIG/LED` 开关拨到**数码管**位（否则全灭） |
| 声音 | HDMI 接带喇叭的显示器，音量先调小 |

## B. 烧写命令（在 `board` 目录执行）

```tcl
# 1) 构建
td_commands_prompt.exe build.tcl

# 2) Flash 烧写
svfgen -chip EG4S20BG256 -bit team_player.bit -svf flash.svf \
       -scan_mode prog_spi -start_addr 0x0 -flash W25Q16JV
program_svf -svf flash.svf -spd 8

# 3) 回读校验
download -mode verify_spi -bit team_player.bit -start_addr 0x0
```

## C. 数码管读数解码（左起 6 位）

| 位 | 含义 | 期望 |
|---|---|---|
| 1 | err | `0` 正常；`F` 图片不足；`C` 音频欠载；`D` 行欠读；`E` 淡入淡出故障；`B` HDMI 未就绪 |
| 2 | as（音频状态） | `4` = 正在读 PCM（有声即正常） |
| 3 | **装图内部错误码** | `0` 正常；`1` BMP 解析；`2` 文件读；`3` 坐标越界；`4` 计数不符；**`5` SDRAM 写后读回失败** |
| 4 | 当前帧号 | 1~4 |
| 5 | **驻留图片数** | **4** |
| 6 | bs（启动阶段） | `5` 正常结束；`6` 失败 |

> 说明：第 3 位是 2026-11-03 新增的诊断位（原为模式位），恢复方法见 `patches/board__team_top.v.diff`。

## D. SDRAM 定位用的独立自检（不依赖主设计）

`artifacts/sdram_self_test/` 里有完整可编译的小设计（只跑 SDRAM 读写 + 数码管显示）：

```powershell
cd artifacts\sdram_self_test
td_commands_prompt.exe build.tcl      # -> top_sdram_test.bit
# 烧写方式同上（Flash + 断电冷启动）
```

数码管显示：`数据低4位 | 5-8位 | 9-12位 | 13-16位 | 收到的读响应个数 | init_done`

| 显示 | 含义 |
|---|---|
| `3 0 0 0 4 1` | **已复现的通过状态**：写 `0xA5A50003` 读回 `0x0003`，4 个读响应 |
| `F F F F 0 1` | 读完全无响应（命令被丢） |
| `F F F F 1 1` | 有 1 个响应但数据没采对 → **单笔事务时序问题** |

## E. 已验证的根因与最短修复路径

### E1 已修复（必要）

`team_sdram_port` 原实现把 `Sdr_busy`/`Sdr_init_ref_vld` 当命令门控：

```verilog
wire available = mem_initialized && !mem_busy && !mem_refresh;  // 旧：命令会被丢
wire available = mem_initialized;                                // 新：与基线一致
```

依据：基线 `SD/frame_fifo_read.v`/`frame_fifo_write.v` 只在 `Sdr_init_done` 上同步，
收发不看 busy/refresh（控制器内部仲裁）。自检 v2（带门控，无响应）vs v3（去门控，数据正确）是决定性对照。

### E2 仍待修（当前阻塞）

单笔事务仍不正确，两个可疑点**都要查**：

1. **写侧建立时间**：写脉冲与地址/数据同拍更新 → SIP 采样到上一拍值。
   建议改成：
   ```verilog
   IDLE:  if (wr_valid) begin addr_r<=wr_addr; din_r<=wr_data; state<=PREP; end
   PREP:  state<=WRITE;                    // 数据已稳定
   WRITE: we<=1; state<=SETTLE;            // 单拍脉冲
   ```
   或把 `we` 拉成 2 拍以放宽采样窗口。
2. **读侧采样点**：`Sdr_rd_en` 与 `Sdr_rd_dout` 可能差一拍。
   建议在自检里同时显示"当拍数据"和"延后一拍数据"，看哪个等于写入值。

### E3 相位与时序

- 自检通过用 **180°**（`CLKC2_CPHASE=9`，基线也是 180°）。144° 未通过。
- 180° 版本重编后 **SWNS −0.565 ns / STNS −18.080 ns**（负裕量），功能通了之后必须收敛。
  可选：162°（`CPHASE=8`）、171° 折中；或对 SIP 边界加 multicycle/false path 并写明理由。

## F. 每次调试后回传

```text
版本：<bit sha256 前 8 位 / 提交 sha>
现象：出图 / 黑屏 / 花屏；四张是否齐全
数码管：__ __ __ __ __ __
音频：有/无，连续/断续
操作：按键序列
异常：无 / 出现时机 + 现象
附件：屏幕照片、数码管照片、烧写日志
```

## G. 修好之后的顺序

1. `VERIFY_ENABLE` 改回 **1**（本目录 `patches` 里有说明；当前交付 bit 是 0，仅用于功能验证）。
2. 四图显示 → 按键/轮播/周期/淡入淡出 → 显示时持续有声。
3. 时序收敛到正裕量 → 连续 10 分钟 + 50 次切图 + 3 次冷启动。
4. 按 `records/BOARD_TEST_RECORD_TEMPLATE.md` 填记录，连同 bit/报告一起提交。
