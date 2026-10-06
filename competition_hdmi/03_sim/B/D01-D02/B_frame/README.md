# B_frame 使用说明

src存放team_frame_latch.v与tb_team_frame_latch.v；sim存放run.do及run_batch.do。

先进入本目录sim，再执行do run.do。INJECT_FAIL=0时10项通过，INJECT_FAIL=1时故意错误应显示TEST_FAIL并保留窗口。模型只验证同域事件锁存。

运行缓存、modelsim.ini、vsim.wlf和临时日志本机保留但不提交；个人证据见05_records/B/D01-D02_工具与帧锁存。
