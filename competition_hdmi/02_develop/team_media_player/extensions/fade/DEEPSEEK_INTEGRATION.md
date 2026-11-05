# 给接续队友harness的集成请求

请将`extensions/fade`中的淡出换图后淡入扩展接入你正在制作的自主架构整机，保留你的存储、音频和其它最新工作。此扩展分支只新增这个目录，基于原交接提交9e5fca2，没有修改基础RTL或原交接manifest。

先读本目录README.md、INTEGRATION.md与PROGRESS.md，检查实际3个生产模块。运行：

```text
python extensions/fade/tools/run_fade_regression.py
```

需要时传`--iverilog-bin`，通过标记为`ALL_PASS cases=30`。GIF为RTL输出预览，不能当作板上演示。

如果你在自己的功能分支上，可先保存本地工作，再取独立提交：

```text
git fetch origin feature/fade-transition
git show --stat origin/feature/fade-transition
git cherry-pick origin/feature/fade-transition
```

先确认该tip只包含本扩展目录再应用；不要为了取扩展强制重置或切换你正在跑的工作副本。若同目录已有你自己的文件，应正常解决冲突并保留双方工作。

将team_fade_effect插在已对齐的显示RGB/HS/VS/DE与RGB_to_AXIS之间。所有输出都有相同两级寄存延迟；不能颜色用新路径、DE/VS用旧路径。frame_tick是视频域消隐期每帧单拍。

把原手动/自动切图事件变为request_valid/ready请求，提供已驻留的目标编号和request_slot_valid。默认step8，效果使能1。实际切帧必须延后到模块发出的switch_valid/ready，而不是按键到来时提前切换。

最关键的适配工作由你完成：保存switch_token/slot，通过你的原子切帧与scanout读FIFO调度，在目标编号采纳、旧数据排空、新首行可读之后，返回匹配的reply_token/slot和一拍reply_valid。现有team_frame_commit_bridge.select_done只说明编号采纳，不能直接当成该回复。

若控制/存储不是video_clk域，实现稳定负载的请求/回应跨域握手。不要直接接窄脉冲、多位token或slot。执行switch_cancel时停止并排空对应旧任务；监督器确认连贯显示恢复后才可通过recover握手解除故障。

本包故障会明确failed/fault并保持黑色同步，需你的监督器处理；切勿把recover_valid绑1或用假成功回复绕过等待。最终检查实际TD资源/时序，再由持板者验证四张图、手动/轮播、效果开关、不同step、复位和长期稳定性，归档真实录像与提交号。

不要把本模块包的仿真通过写成“整机扩展已板测通过”，不要因此篡改原45/100基线或覆盖你的其它工作。基础与扩展最终进度分别更新。
