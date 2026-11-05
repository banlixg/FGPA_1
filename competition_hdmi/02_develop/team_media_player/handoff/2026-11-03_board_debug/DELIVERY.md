# 交付说明：2026-11-03/04 实板调试（SDRAM 已修复，图像已上屏）

> **2026-11-04 最新状态（优先阅读）**
>
> | 项 | 结果 |
> |---|---|
> | SDRAM 写后读回校验 | **通过**（4 拍突发 + PREP 建立 + 去掉 busy 门控，`VERIFY_ENABLE=1`） |
> | 四张 BMP 驻留 | **成功**（数码管 `count=4`、内部错误码 `0`） |
> | 图像上屏 | **成功**（红底 TEAM FRAME 01，方向/色条正确；四张依次 红/绿/蓝/紫） |
> | 淡入淡出 | **通过**（渐暗→全黑→渐亮，约 1.2 s） |
> | KEY2 下一张 / KEY4 轮播 / KEY3 周期 / KEY1 复位 | **全部通过**（实测） |
> | HDMI 音频 | **通过**（4 秒旋律循环，切图期间不断） |
> | 时序 | **收敛**：SWNS **+3.407 ns**、HWNS **+0.022 ns**，0 违反 |
> | 最终 bit | `artifacts/team_player_2026-11-04_timing_closed.bit`，SHA256 `c760102a091d585f7042e8637737e36dc974bc8858c753fcc06bc8a5b6e5ab33` |
> | 待补 | 连续 10 分钟 / 50 次切图 / 3 次冷启动记录 |
>
> **SDRAM 修复三要素**（`rtl/storage/team_sdram_port.v` 已重写）：
> 1. 命令门控：`available = mem_initialized`（不再看 `Sdr_busy`/`Sdr_init_ref_vld`，与基线一致）；
> 2. **单拍写/读在本板 SIP 上不可靠**（有回应但数据 FFFF），改为**写/读各 4 拍突发**，写前地址数据提前一拍稳定（`PREP`）；
> 3. 读回校验恢复为 `VERIFY_ENABLE=1`，比对第 4 个读回应。
>
> **时序例外**（`board/timing.sdc`）：TD 把 SIP 硬核 32 条 DQ 焊盘路径按内部寄存器模型分析，得 −0.565 ns；
> 该路径真实约束是外部 SDRAM 芯片 tAC/板级延迟，SDC 无芯片模型，故对这 32 条焊盘路径加**带理由的源同步例外**，
> 其余时钟域保持完整分析。实板读写校验通过是该项的依据。

---


- 基线提交：`ba5b22103c69071c884819f70e2ab10ff3054625`（`integration/full-player`，100 分制自评 90 分）
- 本目录性质：**新增目录，不覆盖任何既有文件**。原有 `rtl/`、`board/`、`docs/`、`records/`、`release/` 一律未删除、未重命名。
- 交付内容：本轮实板调试的结论、根因、补丁、可烧写 bit、独立自检设计、板测原始记录。
- 自评状态：**仍在调试中，未达成验收**。`board_verified` 仍为 `false`。

---

## 1. 一句话结论

候选版在本板（HX4S20C V1.0 / EG4S20BG256）**已能启动、能读 TF 卡、能放 WAV 音频（4 秒旋律循环）、数码管诊断可用**；
但 **4 张 BMP 一张都装不进帧区**（数码管 `count=0`），因此无图可显示——黑屏。本轮已把失败点从"整机黑箱"收敛到
**SDRAM 写后读回校验失败**（数码管内部错误码 `5`），并给出了两个层次的候选修复与一个独立自检设计用于继续定位。

---

## 2. 本轮时间线与关键结论

| 步骤 | 操作 | 结果 |
|---|---|---|
| 1 | 核对候选包 | `python tools/verify_candidate.py` → `CANDIDATE_PASS files=431`；bit SHA256 与清单一致 |
| 2 | 准备 TF 卡（E:） | 旧素材移到 `E:\_backup_20261103\`；4×IMG + AUDIO.WAV 复制到根目录并逐文件核 SHA256 ✅ |
| 3 | JTAG 下载到 SRAM | 报 `PROGRAM OK`，但**板上配置未改变**（按键 KEY1 能重放旧开机动画得以证实）→ 该板 JTAG 临时配置不可靠，改用 Flash |
| 4 | 烧 QSPI Flash | `svfgen -scan_mode prog_spi` + `program_svf` + `verify_spi` 全通过；断电冷启动后候选版真正运行 |
| 5 | 定位"数码管全灭" | 板载 **SW6（丝印 `DIG/LED`）选择开关**拨在双色 LED 位；拨到数码管位后正常显示 |
| 6 | 读数码管 | 初值 `F40105`：err=F、as=4（音频正常）、mode=0、slot+1=1、count=0、bs=5 |
| 7 | 查黑屏机制 | `team_line_scanout` 中 `pixel_good` 依赖 `active_valid`；无驻留帧 → 整屏纯黑。确认黑屏=无图，不是显示时序问题 |
| 8 | 改 PLL 反馈结构 | 把两颗手改 PLL 改回基线已验证的 `FEEDBK_MODE("NORMAL")+FEEDBK_PATH("CLKC0_EXT")+fbclk(clk0_out)`；并加 4 颗 LED 诊断（心跳/锁/复位） |
| 9 | 加内部错误码显示 | 数码管第 3 位改显示图片加载器内部错误码 → 读数 `F45105` → **内部错误码 = 5 = SDRAM 写后读回校验失败** |
| 10 | 独立 SDRAM 自检 v1 | 用 `team_sdram_port` 做 4 次写-读回校验：`init_done=1`，但 **4/4 失败**（`403202`） |
| 11 | 自检 v2（直连 App 口，仍带 busy 门控） | 读**完全无响应**（`FFFF51`） |
| 12 | 自检 v3（直连 App 口，**去掉 busy/refresh 门控**，4 写 + 4 读） | **通过**：写入 `0xA5A50003` 读回 `0x0003`，4 个读响应全收到（`300041`） |
| 13 | 结论 | SDRAM 硬件与读写都正常；失败源于端口把 `Sdr_busy / Sdr_init_ref_vld` 当门控，命令在刷新切换窗口被静默丢弃（基线从不这样门控） |
| 14 | 修复端口 + 相位 180° | `available = mem_initialized`；`CLKC2_CPHASE 7→9`（180°，与自检/基线一致）。重编后**仍报内部错误码 5**（`F45105`） |
| 15 | 关掉写后读回校验做判定 | 新增参数 `VERIFY_ENABLE`，主设计实例置 0，已生成 bit 并烧写；**板测结果待补**（见第 6 节） |

---

## 3. 已定位的三个问题（含证据）

### 3.1 数码管全灭：板载选择开关，不是 RTL bug

- 本板（HX4S20C V1.0）上 **8 组双色 LED 与 8 位数码管复用 16 个引脚**，由 SW6（丝印 `DIG/LED` / 手册称 SW6）选择。
- 手册：拨上 = 数码管，拨下 = 双色 LED；`SEL[0..5]` 对应"左起第 1~6 个数码管"。
- 候选版 `seg_sel` 低有效、`seg_data` 共阳段码低有效，与参考工程 `seg_scan.v` **完全一致**，极性无误。
- 结论：显示全灭是开关位置；拨到数码管位后 6 位正常扫描。

### 3.2 SDRAM 写后读回校验失败：端口门控丢弃命令（主因）

**证据链**

1. 画面黑屏、`count=0`、内部错误码 `5`（= `team_frame_store_writer` 的 `wr_rsp_error` 分支）。
2. 独立自检 v1（走端口，含门控）：`init_done=1`，写-读回 4/4 失败。
3. 自检 v2（直连 App 口 + `!busy && !refresh` 门控）：**读响应一个都收不到**（超时，数据保持 `FFFF`）。
4. 自检 v3（直连 App 口，**去掉门控**，连发 4 写 + 4 读）：**完全正确**，`0xA5A50003 → 0x0003`，`rd_cnt=4`。
5. 基线参考实现（`SD/frame_fifo_read.v`、`frame_fifo_write.v`）：只在 `Sdr_init_done` 上同步，
   **收发命令从不看 `Sdr_busy` / `Sdr_init_ref_vld`**，刷新由 SIP 控制器内部仲裁。

**修复**：`rtl/storage/team_sdram_port.v` 中
```verilog
wire available = mem_initialized && !mem_busy && !mem_refresh;   // 旧（错误）
wire available = mem_initialized;                                 // 新
```
**注意**：该修复单独上板后仍报错误码 5（见 3.3 与第 6 节），说明门控是**必要但不充分**，单笔写-读回尚有别的问题。

### 3.3 单笔写 → 单笔读 与 连发多笔 行为不同

- 自检 v4（单笔写 `0xA5A51234` → 64 拍 → 单笔读）：出现 **1 个读响应**（`rd_cnt=1`），但读回数据为占位值 `FFFF`。
- 与 v3（多笔连发，数据正确）对比可知：**单笔事务的写数据/地址建立时机**或**读数据采样时机**存在偏差。
- 已怀疑：`App_wr_en` 脉冲发出当拍，`App_wr_din/App_wr_addr` 与脉冲同拍更新（SIP 采样到的是上一拍值）；
  若 SIP 在 `App_wr_en` 之后一拍才采样数据，则多笔连发时"整体右移"仍能落到相同地址序列，而单笔会丢掉唯一一笔。

---

## 4. 本轮修改清单（7 文件，另有 1 个新增参数）

| 文件 | 改动 | 目的 |
|---|---|---|
| `board/team_mem_pll.v` | 反馈改回基线 `NORMAL` + `CLKC0_EXT` + `fbclk(clk0_out)`；`CLKC2_CPHASE 7→9`（144°→180°） | PLL 锁定与 SDRAM 移位时钟相位对齐基线 |
| `board/team_video_pll.v` | 改为基线 `video_pll.v` 的**逐字副本**（25/125 MHz） | 消除手改参数风险 |
| `board/team_top.v` | 新增 4 颗 LED 诊断；数码管第 3 位改显示装图内部错误码 | 板上可观测性 |
| `board/pin.adc` | 新增 `led[0..3]` 引脚（A4/A3/C10/B12） | 同上 |
| `rtl/storage/team_sdram_port.v` | `available` 去掉 busy/refresh 门控；新增参数 `VERIFY_ENABLE` | 修主因；提供"关校验"功能验证开关 |
| `rtl/storage/team_boot_loader.v` | 新增输出 `last_image_error` | 把装图失败原因送上数码管 |
| `rtl/team_player_core.v` | 引出 `boot_detail`；端口实例 `VERIFY_ENABLE(0)` | 诊断通路 + 功能验证 |

- 补丁：`patches/ALL_CHANGES.diff`（可直接 `patch -p1` 应用）
- 完整改后文件：`modified_sources/`（也可直接覆盖到工程对应路径）

---

## 5. 关键实验数据（数码管读数，左起 6 位）

| 版本 | 读数 | 解码 | 结论 |
|---|---|---|---|
| candidate_01（原样） | `F 4 0 1 0 5` | err=F, as=4, mode=0, slot+1=1, count=0, bs=5 | 无图驻留，黑屏 |
| 加内部错误码后 | `F 4 5 1 0 5` | **内部错误码=5** | 失败点在 SDRAM 写后读回 |
| SDRAM 自检 v1（走端口） | `4 0 b 2 0 0` | fail=4, pass=0, {mi,st}=b→mi=1,st=3, {lock,mb}=2 | 初始化成功、校验全失败 |
| 自检 v2（直连+门控） | `F F F F 5 1` | 数据未更新、rd_cnt=0、状态=5 超时 | **读完全无响应** |
| 自检 v3（直连+无门控） | `3 0 0 0 4 1` | 数据 0x0003、rd_cnt=4 | **读写正常**（根因=门控） |
| 自检 v4（单笔） | `F F F F 1 1` | 数据占位、rd_cnt=1 | 有响应但数据未正确采样 |
| 端口修正 + 180° 相位 | `F 4 0 1 0 5` → 加诊断 `F 4 5 1 0 5` | 仍报 5 | 门控是必要不充分 |
| `VERIFY_ENABLE=0` | **待补** | — | 最后一步待板上验证 |

> 数码管位定义（候选版原设计，左起）：`err | as | (mode) | slot+1 | count | bs`；
> 诊断版把第 3 位换成 `内部错误码`。
> 内部错误码：1=BMP 解析错 2=文件读错 3=坐标越界 4=像素计数不符 **5=SDRAM 写后读回失败** 6=其他。

---

## 6. 当前状态（务必如实转述）

**已通过**

- 候选包完整性（431 文件校验）
- TF 卡素材准备与逐文件哈希核对
- QSPI Flash 烧写 + `verify_spi` 回读校验
- 断电冷启动后候选版真正运行（非旧设计）
- 数码管诊断、内部错误码显示、LED 诊断可用
- SD 初始化、FAT32 挂载、目录枚举、WAV 解析、PCM→I2S→HDMI 音频链路：**4 秒旋律稳定循环**（本轮实测）
- SDRAM 控制器初始化成功；**直连 App 口（不加 busy 门控）读写数据正确**

**未通过（阻塞点）**

- 4 张 BMP 无法驻留帧区（`count=0`），因此**无图像显示**
- `team_sdram_port` 的写后读回校验在单笔事务下仍失败（错误码 5）
- 最后一版 `VERIFY_ENABLE=0` 的 bit 已烧写，但**板测结果尚未回报**（这是本目录交付时最大的未知项）

**已知风险 / 未验收项**

- 本轮重编后时序为 **SWNS −0.565 ns / STNS −18.080 ns**（负裕量），来自 180° 相位下 `mem_clk` 与移位时钟之间的路径；
  功能验证后必须收敛（或改回 144° 并另找单笔失败的根因）。
- `VERIFY_ENABLE=0` 会**取消"写后读回校验"这一设计特性**，仅用于定位；正式版必须恢复为 1。
- 按键（KEY2/4/3）、淡入淡出、轮播、复位重载、10 分钟连续运行、Flash 冷启动**均未做验收**
  （因图像未上屏，这些功能无法观察）。
- 未做真实 TF 卡长时间读取压力与 SDRAM 带宽测试。

---

## 7. 复现步骤（队友接手）

```powershell
# 0) 目录：本目录所在工程根（competitive_hdmi/02_develop/team_media_player）
# 1) 应用本轮修改（二选一）
#    a. 打补丁
patch -p1 < handoff/2026-11-03_board_debug/patches/ALL_CHANGES.diff
#    b. 或直接覆盖
#       handoff/2026-11-03_board_debug/modified_sources/*.v|adc → 对应 board/ 与 rtl/ 路径

# 2) 重建（TD 6.2，工程内自带 build.tcl）
td_commands_prompt.exe <board/build.tcl 所在目录执行>
#    产物：board/team_player.bit

# 3) 烧 Flash（JTAG 临时配置在本板不可靠，已验证必须走 Flash + 断电冷启动）
svfgen -chip EG4S20BG256 -bit board/team_player.bit `
       -svf flash.svf -scan_mode prog_spi -start_addr 0x0 -flash W25Q16JV
program_svf -svf flash.svf -spd 8
download -mode verify_spi -bit board/team_player.bit -start_addr 0x0

# 4) 断电 → 上电，数码管开关（丝印 DIG/LED）拨到"数码管"位
# 5) 读数码管 6 位，对照第 5 节解码
```

SDRAM 自检（诊断用，独立于主设计，可直接烧）：

```powershell
cd handoff/2026-11-03_board_debug/artifacts/sdram_self_test
td_commands_prompt.exe build.tcl     # 产物 top_sdram_test.bit
# 烧写方式同上；数码管显示：数据低4位|5-8位|9-12位|13-16位|读响应数|初始化
```

---

## 8. 建议的下一步（按优先级）

1. **先确认 `VERIFY_ENABLE=0` 版本的板测现象**（已烧写）：若图像上屏 → 显示读通路正常，
   问题被完全限定在写后读回校验逻辑，可专注修端口；若仍黑屏但 `count=4` → 问题在行读取/扫描输出。
2. 修单笔事务时序：写数据与地址在 `App_wr_en` **之前一拍**稳定，或把写脉冲拉到 2 拍；
   读回数据的采样点再确认（`Sdr_rd_en` 与 `Sdr_rd_dout` 的对齐）。
3. 收敛时序：180° 相位下 SWNS 为负；可尝试 162°/171° 折中，或对 SIP 边界加 `set_multicycle_path`/`set_false_path` 并说明理由。
4. 恢复 `VERIFY_ENABLE=1` 后再做正式验收：四图/方向/颜色、淡出淡入、按键、轮播、复位、10 分钟连续、Flash 冷启动。
5. 修订 `PROGRESS.md` 与 `docs/板上验收_2026-10-26.md`：把本轮实测结论并入（本目录不改原文档，避免覆盖）。

---

## 9. 文件清单

```
handoff/2026-11-03_board_debug/
├── DELIVERY.md                      本文件（交付说明）
├── ANALYSIS.md                      根因分析详解（时序/门控/单笔事务）
├── README.md                        3 步快速验证
├── patches/
│   ├── ALL_CHANGES.diff             全部改动（patch -p1 可用）
│   └── *.diff                       逐文件补丁
├── modified_sources/                改后完整文件（可直接覆盖）
├── artifacts/
│   ├── team_player_2026-11-03.bit   本轮最终 bit（VERIFY_ENABLE=0 功能验证版）
│   ├── team_player_2026-11-03.bit.sha256
│   └── sdram_self_test/             独立 SDRAM 自检设计（源码 + bit + 构建脚本 + 构建日志）
└── records/
    ├── README.md                    板测记录（含 TF 卡准备、下载日志、观察项）
    ├── program_sram.log             JTAG 下载日志（证明"报 OK 但不生效"）
    ├── program_sram_after_card_insert.log
    └── build_summary.log            重编时序/资源摘要
```

---

## 10. 诚实性声明

- 本目录所有"通过"均指 **实板现象 + 数码管/LED 读数**，没有把仿真或"生成 bit"当成板测通过。
- 未完成的项在第 6 节明确列出，不以"应该可以"代替验证。
- 音频能响是本轮实测事实；但**图像仍未上屏**，因此不能宣称播放器验收通过。
- 最后一版 bit（`VERIFY_ENABLE=0`）的板测结果尚缺，接手队友应优先补齐。
