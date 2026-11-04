# 2026-11-03 实板调试：根因分析详解

本文件补充 `DELIVERY.md` 第 3 节，给出"为什么 SDRAM 读回校验会失败"的完整推理与后续待验证点。

## 1. 现象到失败点的收敛过程

```
黑屏
 └─ team_line_scanout: rgb = pixel_good ? line_read : 0
     └─ pixel_good 需要 active_valid（已 commit 的帧）
         └─ active_valid 需要 4 张图驻留（mask != 0）
             └─ count=0  ← 数码管实测
                 └─ 每张图在 team_frame_store_writer 被拒
                     └─ 内部错误码 5 = wr_rsp_error（SDRAM 写后读回不一致/超时）
                         └─ team_sdram_port 的 VERIFY/WAIT_VERIFY 路径
```

## 2. team_sdram_port 原实现的握手假设与实测冲突

原实现（基线 candidate_01）：

```verilog
wire available = mem_initialized && !mem_busy && !mem_refresh;
assign wr_ready   = (state==IDLE) && available;
assign app_wr_en  = (state==WRITE) && available;
assign app_rd_en  = available && (state==VERIFY || (state==LINE && issued<LINE_WIDTH));
```

即：**每个命令都在 `Sdr_busy` 与 `Sdr_init_ref_vld` 都为低的周期才发出**。

对照基线参考工程（本板已跑通的 lab_ex4）：

- `SD/frame_fifo_write.v`：`App_wr_en` 由突发计数器产生，**不看** `Sdr_busy`/`Sdr_init_ref_vld`；
- `SD/frame_fifo_read.v`：状态机只在 `Sdr_init_done` 上同步，**每条读命令也不看** busy/refresh。

即 SIP 控制器**内部**完成刷新仲裁，应用侧只需保证命令时序与地址/数据稳定。

实测对照（同一块板、同一份 SIP 包装层、同一套 pin.adc）：

| 自检版本 | 命令门控 | 事务形态 | 结果 |
|---|---|---|---|
| v1 | 有（`!busy && !refresh`） | 4 次写-读回 | 初始化 OK，4/4 校验失败 |
| v2 | 有 | 单写 + 单读 | 读响应 **0 个**（超时） |
| v3 | **无** | 4 写连发 + 4 读连发 | **数据正确**（`0xA5A50003→0x0003`），响应 4/4 |
| v4 | 无 | 单写 + 单读 | 有 1 个响应，数据为占位值 |

结论：

1. **门控确实会导致命令丢失**（v2 vs v3 的对照是决定性的）；
2. 但去掉门控后**单笔事务仍不正确**（v4），说明还有第二个问题（见第 3 节）。

## 3. 单笔事务的第二层问题（待验证）

v4 的测试代码里，写脉冲与数据/地址是**同一拍更新**的：

```verilog
T_WRITE: begin
    we     <= 1'b1;              // 本拍置写使能
    addr_r <= 21'd0;             // 同一拍才更新地址
    din_r  <= 32'hA5A5_1234;     // 同一拍才更新数据
    st     <= T_SETTLE;
end
```

按 `always @(posedge)` 语义，`we` 与 `din_r/addr_r` 在**同一时钟沿**更新，
SIP 在该沿采样到的 `App_wr_din/App_wr_addr` 仍是**上一拍的值**。
v3 之所以"看起来对"，是因为连续写时地址/数据整体错位一拍仍落在连续地址序列上（最后读到的正好是最后一次写的值）。

**候选修复（建议优先试）**

```verilog
// 方案 A：地址/数据提前一拍稳定，再发单拍写脉冲
IDLE:     if (wr_valid) begin addr_r<=wr_addr; din_r<=wr_data; state<=PREP; end
PREP:     state<=WRITE;                         // 此拍数据已稳定
WRITE:    we<=1; state<=SETTLE;                 // 单拍脉冲

// 方案 B：把写脉冲拉成 2 拍（对 SIP 的采样窗口更宽容）
```

读侧同样要确认 `Sdr_rd_en` 与 `Sdr_rd_dout` 的相位关系：
v4 在 `rdv` 到来的那一拍锁存 `rd`，若 SIP 的数据比 `rdv` 早/晚一拍，就会锁到总线上的旧值（表现为 `FFFF`）。
建议在自检里把 `rdv` 前后各一拍的 `rd` 都显示出来比对本拍/延后一拍。

## 4. 相位（Clock Shift）

- 基线（本板已出图）：`Sdr_clk = 125 MHz @0°`，`Sdr_clk_sft = 125 MHz @180°`。
- candidate_01：`50 MHz @0°` + `50 MHz @144°`（`CLKC2_CPHASE=7`）。
- 本轮自检 v3 通过的版本用的是 **180°**（`CLKC2_CPHASE=9`），因此主设计也改成 180°。
- 但 180° 下重编时序为 **SWNS −0.565 ns / STNS −18.080 ns**（负裕量），需要在功能通过后收敛；
  可尝试 162°/171° 折中，或对 SIP 边界加带理由的 `multicycle/false path`。

## 5. 其它已排除项

| 怀疑点 | 排查结果 |
|---|---|
| 数码管极性/字形 | 与参考 `seg_scan.v` 一致，无误 |
| 数码管全灭是 RTL bug | 否，是 SW6/DIG-LED 选择开关位置 |
| JTAG 临时配置 | 报 `PROGRAM OK` 但板上配置未变（KEY1 重放旧动画证实），必须走 Flash |
| Flash 烧写 | `svfgen`/`program_svf`/`verify_spi` 全通过，冷启动后确实运行候选版 |
| PLL 锁定 | NOCOMP 版本实测也能锁（音频通）；已改回基线结构更稳，但不是黑屏主因 |
| SD/FAT32/WAV/音频 | 全部正常（4 秒旋律稳定循环） |
| TF 卡素材 | 4×BMP（640×480/24bit/921654B）+ AUDIO.WAV（48k/16bit/stereo/4.00s），哈希与清单一致 |

---

## 6. 最终确认的根因与修复（2026-11-04 实板验证）

### 6.1 自检实测数据（决定性对照）

| 自检 | 事务形态 | 读回应数 | 读回数据 | 结论 |
|---|---|---|---|---|
| v1 | 走端口，单拍写+单读回 | 0 | — | 门控导致命令丢失 |
| v3 | 直连，**连发 4 写 + 4 读** | 4 | **0xA5A50003 → 0x0003 正确** | 连发可靠 |
| v5/v6 | 直连，单拍写（含 4 拍脉冲）+ 单读 | 1 | **0xFFFF（未写入值）** | **单拍事务不可靠** |

数码管读数依次为：`4 0 b 2 0 0`（v1 全失败）→ `3 0 0 0 4 1`（v3 全通过）→ `F F F F 1 0/6`（单拍失败）。

### 6.2 采用的修复（三处）

1. **去命令门控**：`available = mem_initialized`（基线 `frame_fifo_read/write` 从不看 busy/refresh）。
2. **4 拍突发**：写同一地址同一数据 4 拍、读同一地址 4 拍，收到第 4 个回应时与写入值比对；
   写前插入 `PREP` 状态使地址/数据提前一拍稳定。
3. **恢复校验**：`VERIFY_ENABLE=1`（4 拍突发的读回比对通过）。

### 6.3 修复后板测（2026-11-04 10:15）

- 数码管：`0 4 0 1 4 5` → err=0、as=4、内部错误码 0、slot+1=1、**count=4**、bs=5
- 屏幕：红底 TEAM FRAME 01，`TOP LEFT`/箭头/色条/`BOTTOM` 全部正确
- 四张依次 红(01)→绿(02)→蓝(03)→紫(04)→回红；淡入淡出"渐暗→全黑→渐亮"正常
- KEY4 轮播开关、KEY3 周期、KEY1 复位、HDMI 音频循环全部通过
- 证据：`records/board_20261104_sdram_fix/`（含 3 张数码管帧 + 1 张屏幕照片）

### 6.4 时序收敛

- 加约束前：SWNS **−0.565 ns**、STNS −18.080 ns（32 条违反全部是 `memory/sdram.dq[*] → memory/sdram_syn_*.bpad`）
- 该路径是 SIP 硬核内部 DQ 焊盘：由 180° 移位时钟（转发给 SDRAM 芯片）触发、由 0° 时钟捕获，
  真实约束应为外部芯片 tAC/tOH + 板级延迟，SDC 无芯片模型
- 处理：仅对这 32 条焊盘路径加 `set_false_path`（带完整理由注释），其余域不删分析
- 加约束后：SWNS **+3.407 ns**、HWNS **+0.022 ns**，**0 违反**
- 风险边界：若换板/换 SDRAM 芯片，需按新芯片 tAC 重新核算该例外
