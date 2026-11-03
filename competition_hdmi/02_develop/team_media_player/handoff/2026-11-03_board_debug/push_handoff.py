#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""把 handoff/2026-11-03_board_debug 推到 GitHub 的新分支（只新增该目录）。

用法（token 从环境变量 GH_TOKEN 读，避免出现在命令行/日志里）：
    set GH_TOKEN=github_pat_xxx
    python tools/push_handoff.py

流程：Git Data API —— blob(逐文件) → tree(base_tree=基线提交的树) → commit → ref(新分支)
不会修改任何既有文件，也不动 integration/full-player 分支本身。
"""
import base64
import io
import json
import os
import sys
import urllib.error
import urllib.request

REPO = "banlixg/FGPA_1"
BASE_BRANCH = "integration/full-player"
NEW_BRANCH = "handoff/2026-11-03-board-debug"
API = "https://api.github.com"

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
# 脚本本身就放在要上传的目录里
LOCAL_DIR = HERE
REMOTE_PREFIX = "competition_hdmi/02_develop/team_media_player/handoff/2026-11-03_board_debug"


def req(method, path, token, payload=None):
    url = API + path
    data = json.dumps(payload).encode() if payload is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", "Bearer " + token)
    r.add_header("Accept", "application/vnd.github+json")
    r.add_header("User-Agent", "dsh-handoff-push")
    r.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data:
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=90) as resp:
            body = resp.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:800]
        raise SystemExit("HTTP %s %s -> %s\n%s" % (e.code, method, path, detail))


def main():
    token = os.environ.get("GH_TOKEN", "").strip()
    if not token:
        tf = os.path.join(os.environ.get("TEMP", "."), "gh_token.txt")
        if os.path.exists(tf):
            token = io.open(tf, encoding="utf-8").read().strip()
            print("token: 从临时文件读取（%d 字符）" % len(token))
    if not token:
        print("请先设置环境变量 GH_TOKEN")
        return 2
    if not os.path.isdir(LOCAL_DIR):
        print("本地目录不存在:", LOCAL_DIR)
        return 2

    me = req("GET", "/repos/" + REPO, token)
    print("repo:", me["full_name"], "| default:", me["default_branch"], "| private:", me["private"])

    ref = req("GET", "/repos/%s/git/ref/heads/%s" % (REPO, BASE_BRANCH), token)
    base_sha = ref["object"]["sha"]
    base_commit = req("GET", "/repos/%s/git/commits/%s" % (REPO, base_sha), token)
    base_tree = base_commit["tree"]["sha"]
    print("base:", BASE_BRANCH, base_sha[:12])

    files = []
    for root, _dirs, names in os.walk(LOCAL_DIR):
        for n in names:
            full = os.path.join(root, n)
            rel = os.path.relpath(full, LOCAL_DIR).replace("\\", "/")
            files.append((rel, full))
    files.sort()
    print("待上传文件数:", len(files))

    tree_items = []
    for rel, full in files:
        raw = open(full, "rb").read()
        blob = req("POST", "/repos/%s/git/blobs" % REPO, token,
                   {"content": base64.b64encode(raw).decode(), "encoding": "base64"})
        path = REMOTE_PREFIX + "/" + rel
        tree_items.append({"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]})
        print("  blob %-62s %8d B" % (rel, len(raw)))

    tree = req("POST", "/repos/%s/git/trees" % REPO, token,
               {"base_tree": base_tree, "tree": tree_items})
    msg = ("handoff: 2026-11-03 board debug (SD card prep, flash boot, "
           "PLL/seg/SDRAM diagnosis)\n\n"
           "- new directory only: " + REMOTE_PREFIX + "\n"
           "- base: " + BASE_BRANCH + " @ " + base_sha[:12] + "\n"
           "- see DELIVERY.md / ANALYSIS.md inside the directory")
    commit = req("POST", "/repos/%s/git/commits" % REPO, token,
                 {"message": msg, "tree": tree["sha"], "parents": [base_sha]})
    print("commit:", commit["sha"])

    try:
        req("POST", "/repos/%s/git/refs" % REPO, token,
            {"ref": "refs/heads/" + NEW_BRANCH, "sha": commit["sha"]})
        print("新分支已创建:", NEW_BRANCH)
    except SystemExit as e:
        # 分支已存在 -> 更新引用
        print("分支已存在，改为更新引用")
        req("PATCH", "/repos/%s/git/refs/heads/%s" % (REPO, NEW_BRANCH), token,
            {"sha": commit["sha"], "force": False})
        print("分支已更新:", NEW_BRANCH)

    print("完成：https://github.com/%s/tree/%s/%s" % (REPO, NEW_BRANCH.replace("/", "%2F"), REMOTE_PREFIX))
    return 0


if __name__ == "__main__":
    sys.exit(main())
