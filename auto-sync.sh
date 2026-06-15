#!/bin/bash
# Claude 工作空间自动同步脚本（单次 push + MCP 精细化清理）
# 模式说明：
#   默认模式：仅同步，不删除本地用户文件
#   清理模式：同步后将成功索引/重复的归档文件从本地移除（保留 GitHub 历史版本）

REPO_DIR="$HOME/工作"
cd "$REPO_DIR" || exit 0

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

ARCHIVE_DIR="待归档"
SYNC_SCRIPT="$REPO_DIR/sync-to-mcp.py"

# ---------- 1. 检查是否有待归档文件 ----------
HAS_ARCHIVE_FILES=0
if [ -d "$ARCHIVE_DIR" ] && [ -n "$(find "$ARCHIVE_DIR" -type f -not -path '*/\.*' 2>/dev/null)" ]; then
    HAS_ARCHIVE_FILES=1
fi

# ---------- 2. 检查是否有其他变更 ----------
git add -A
HAS_STAGED_CHANGES=0
if ! git diff --cached --quiet; then
    HAS_STAGED_CHANGES=1
fi

# 没有任何事情要做
if [ "$HAS_ARCHIVE_FILES" -eq 0 ] && [ "$HAS_STAGED_CHANGES" -eq 0 ]; then
    echo "[auto-sync] 没有变更，跳过"
    exit 0
fi

# ---------- 3. 提交非归档/归档的主变更（暂不 push） ----------
if [ "$HAS_STAGED_CHANGES" -eq 1 ]; then
    git commit -m "sync: $(date '+%Y-%m-%d %H:%M:%S')" --no-verify
    echo "[auto-sync] 已提交主变更"
fi

# ---------- 4. 同步 待归档 到 evolving-knowledge-mcp 并精细化清理 ----------
if [ "$HAS_ARCHIVE_FILES" -eq 1 ] && [ -f "$SYNC_SCRIPT" ]; then
    echo "[auto-sync] 同步待归档文件到 evolving-knowledge-mcp..."
    if python3 "$SYNC_SCRIPT" --cleanup "$ARCHIVE_DIR"; then
        echo "[auto-sync] MCP 索引与精细化清理完成"
    else
        echo "[auto-sync] ⚠️ MCP 索引失败，已提交的主变更未 push，待归档文件保留本地供重试"
        exit 0
    fi
fi

# ---------- 5. 提交清理变更（如有） ----------
git add -A
if ! git diff --cached --quiet; then
    git commit -m "chore: auto cleanup 待归档 files after sync" --no-verify
    echo "[auto-sync] 已提交清理变更"
fi

# ---------- 6. 统一 push 到 GitHub ----------
git push origin main
echo "[auto-sync] 已推送到 GitHub"
