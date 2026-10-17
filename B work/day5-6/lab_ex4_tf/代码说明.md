# lab_ex4_tf — TF 卡 BMP 轮播 + HDMI 1.4b 视频显示

本目录为 **APUG092_HDMI1.4b_Transmitter_V1.4** 工程的纯视频播放版本，专注于 TF 卡读取、HDMI 视频输出及可靠性提升。

完整版《设计参考例程》文档见 **[设计参考例程文档.md](设计参考例程文档.md)** / **[设计参考例程文档.docx](设计参考例程文档.docx)**。

## 1. 工程功能简介

本工程实现了一个基于安路 FPGA 的多媒体播放系统，主要功能与特点如下：

1. 从 TF 卡中读取 BMP 图片；
2. 支持最多四张图片自动扫描与加载，采用 SDRAM 双缓冲无缝切换；
3. 通过开发板的 HDMI_B 接口在显示器上显示图片；
4. 支持 **key1** 手动切换下一张图片；
5. 支持 **key2** 开启或关闭自动轮播；
6. 具备完善的**上电防抖复位（POR）机制**：确保所有 PLL 完全锁定且稳定后才启动系统，防止因上电时钟抖动导致花屏或死机；
7. 具备**SD 卡读取防死锁机制**：如果 TF 卡中的图片损坏、截断或非标准分辨率，底层状态机将在 1 秒超时后自动强制中止并恢复控制权，确保系统持续运行。


---

## 2. TF 卡图片格式要求

TF 卡中的图片必须满足以下要求：

```text
图片格式：BMP
分辨率：640 × 480
颜色格式：24-bit RGB
压缩方式：非压缩
```

注意事项：

1. 不能直接把 PNG、JPG 改后缀为 `.bmp`；
2. 必须使用真正的 BMP 文件；
3. 建议 TF 卡格式化为 FAT32；
4. **推荐使用本工程提供的 Python 辅助脚本来处理图片和同步 SD 卡**。

### Python 辅助脚本 (位于 `doc/convert` 目录)
我们在 `convert` 文件夹中提供了两个极其方便的辅助脚本，免去了手工调整图片和解决 FPGA 物理扇区缓存残留的问题：
- **`convert_images_to_bmp.py`**：一键将任何常见的格式（JPG、PNG、WebP 等）批量转换为严格符合 FPGA 要求的 `640x480 24位无压缩 BMP` 格式。
- **`sync_to_sd.py`**：SD 卡一键安全同步工具。由于直接在电脑上删除旧图片往往**无效**（旧图片的物理数据会残留在底层扇区中导致 FPGA 读取出错），该脚本会自动破坏 SD 卡中所有旧图片的文件头、清空数据并写入新图片，彻底防止死锁和读到旧图。详细使用请参考 `convert/README.md`。

---

## 3. 硬件连接要求

开发板上有两个 HDMI 接口，本工程需要使用：

```text
HDMI_B
```

连接方式如下：

```text
开发板 HDMI_B → HDMI 线 → 显示器
```

注意事项：

1. HDMI 线必须插在开发板的 `HDMI_B` 接口上；
2. 图像通过 `HDMI_B` 接口完成输出。

---

## 4. 工程文件位置

Anlogic TD 工程文件位于：

```text
HDMI1.4b_Transmitter/lab_ex4_tf/src/td_project/lab_ex5_i2s_v1.0.al
```

打开工程时，使用 Anlogic TD 直接打开该 `.al` 文件。

---

## 5. 示例图片位置

TF 卡测试用图片位于：

```text
HDMI1.4b_Transmitter/lab_ex4_tf/doc/TF卡图片
```

使用时，可将该目录下符合要求的 BMP 图片复制到 TF 卡中，或使用 `convert` 目录下的脚本一键同步。

---

## 6. 代码文件位置

主要代码文件位于：

```text
HDMI1.4b_Transmitter/lab_ex4_tf/src/user_source/hdl_source
HDMI1.4b_Transmitter/lab_ex4_tf/src/user_source/ip_source
HDMI1.4b_Transmitter/lab_ex4_tf/src/user_source/constraints_source
```

## 7. 最简复现说明

只需要确认以下三点：

```text
工程文件：
HDMI1.4b_Transmitter/lab_ex4_tf/src/td_project/lab_ex5_i2s_v1.0.al

代码文件：
HDMI1.4b_Transmitter/lab_ex4_tf/src/user_source/hdl_source
HDMI1.4b_Transmitter/lab_ex4_tf/src/user_source/ip_source
HDMI1.4b_Transmitter/lab_ex4_tf/src/user_source/constraints_source

示例图片：
HDMI1.4b_Transmitter/lab_ex4_tf/doc/TF卡图片
```

然后将 `doc/TF卡图片` 中的 BMP 图片复制到 TF 卡（或者使用 `convert` 脚本工具生成并同步），将 HDMI 线插入开发板的 `HDMI_B` 接口并连接显示器，打开工程并下载到 FPGA，即可复现 HDMI 图片轮播功能。
