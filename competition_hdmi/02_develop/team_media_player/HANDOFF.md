# 接续入口（2026-10-26）

当前分支`integration/full-player`，整体90/100。45分工程已经接成带文件PCM和淡入淡出的独立播放器，接下来需要实板结果。

- 用法：[板上验收教程](docs/板上验收_2026-10-26.md)
- 源码：`rtl/team_player_core.v`，物理壳`board/team_top.v`
- 工程：`board/team_player.al`
- 下载：`release/2026-10-26_candidate_01/team_player.bit`
- 素材：相邻`media`里的4个BMP和AUDIO.WAV，普通复制到FAT32根目录
- 范围、证据、剩余项：[PROGRESS.md](PROGRESS.md)
- 当前冻结清单：发布副本根目录`CANDIDATE_MANIFEST.json`，用`python tools/verify_candidate.py`只读核对

旧45分handoff文档原样保存在`docs/history/HANDOFF_45_2026-10-24.md`。旧`HANDOFF_MANIFEST.json`与DeepSeek交接提示对应旧冻结包，不能用于断言当前新分支仍是45分或覆盖当前源码。

本版采用一条持续背景WAV，未实现图像切换时更换独立音轨。尚无本版真实板测、扬声器、Flash冷启动证据；所有通过状态须注明是模型、TD还是实板。
