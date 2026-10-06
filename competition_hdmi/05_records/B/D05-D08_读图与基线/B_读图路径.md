# B 读图路径阅读记录

以下是本次核实的阅读起点；个人读过后补上自己副本的路径、行号及解释。

1. bmp_read.v读取扇区字节，通过header_match识别BM、640×480、24位及无压缩字段。pixel_offset指向像素数据，file_len限制有效文件区域。三个字节组成一个24位像素，bmp_data_wr_en发出像素写使能。
2. sd_card_bmp.v扫描范围参数为0—131071，目标数量4。源读取结束阶段由bmp_ready在实际状态上下文中表示；source_done_seen记住源送完，write_finish_pulse来自写帧完成toggle的同步检测。
3. 两种完成都满足后才发布候选显示缓存。disp_buf_idx是缓存身份。真正读端采纳与屏幕有效像素仍需继续追踪frame_fifo_read及video_delay等路径。
4. 图像源数据送完、整帧写完、读端采纳、屏幕有效像素输出有各自的时机。前三天的锁存练习尚未与上述真实事件连接。

| 文件/信号 | 个人副本路径与行号 | 我自己的解释 | 未确认问题 |
|---|---|---|---|
| bmp_read/header_match | 待填写 | 待填写 | 待填写 |
| bmp_read/pixel_offset/file_len | 待填写 | 待填写 | 待填写 |
| sd_card_bmp/bmp_ready | 待填写 | 待填写 | 待填写 |
| source_done_seen/write_finish_pulse | 待填写 | 待填写 | 待填写 |
| disp_buf_idx | 待填写 | 待填写 | 待填写 |
| top/frame_write_toggle_mem | 待填写 | 待填写 | 待填写 |
| 后续读端采纳和像素路径 | 待填写 | 待填写 | 待填写 |
