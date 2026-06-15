#!/bin/bash
# Claude 工作空间自动同步脚本（支持上传后自动清理）
# 模式说明：
#   默认模式：仅同步，不删除本地文件
#   清理模式：同步后停止跟踪并删除本地用户文件（保留仓库基础设施）

REPO_DIR="$HOME/工作"
cd "$REPO_DIR" || exit 0

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    exit 0
fi

# 获取环境变量控制是否清理（CLaude 调用时默认不清理，手动调用可设置 CLEANUP=1）
CLEANUP_MODE="${CLEANUP:-0}"

# 关键基础设施文件（永不删除）
CRITICAL_FILES=(".gitignore" "auto-sync.sh" "README.md" "cleanup.sh" "sync-to-mcp.py")

is_critical() {
    local target="$1"
    for f in "${CRITICAL_FILES[@]}"; do
        if [ "$target" = "$f" ]; then
            return 0
        fi
    done
    return 1
}

# ---------- 1. 暂存所有变更 ----------
git add -A
HAS_OTHER_CHANGES=0
if ! git diff --cached --quiet; then
    HAS_OTHER_CHANGES=1
else
    echo "[auto-sync] 没有非归档变更"
fi

# 获取被暂存的文件列表
STAGED_FILES=$(git diff --cached --name-only)

# ---------- 2. 提交并推送（如有非归档变更） ----------
if [ "$HAS_OTHER_CHANGES" -eq 1 ]; then
    git commit -m "sync: $(date '+%Y-%m-%d %H:%M:%S')" --no-verify
    git push origin main
    echo "[auto-sync] 已推送到 GitHub"
fi

# ---------- 3. 同步 待归档 文件到 evolving-knowledge-mcp ----------
ARCHIVE_DIR="待归档"
SYNC_SCRIPT="$REPO_DIR/sync-to-mcp.py"
if [ -f "$SYNC_SCRIPT" ] && [ -d "$ARCHIVE_DIR" ]; then
    echo "[auto-sync] 同步待归档文件到 evolving-knowledge-mcp..."
    if python3 "$SYNC_SCRIPT" "$ARCHIVE_DIR"; then
        echo "[auto-sync] MCP 索引完成"
    else
        echo "[auto-sync] ⚠️ MCP 索引失败，跳过待归档清理以保留文件重试"
        # 不再继续清理待归档目录
        exit 0
    fi
fi

# ---------- 4. 方案B：自动清理待归档目录 ----------
ARCHIVE_DIR="待归档"
if [ -d "$ARCHIVE_DIR" ]; then
    echo "[auto-sync] 清理待归档目录..."

    # 获取待归档目录下所有被跟踪的文件（禁用 quotepath 避免中文转义）
    ARCHIVE_FILES=$(git -c core.quotepath=false ls-files "$ARCHIVE_DIR/")

    if [ -n "$ARCHIVE_FILES" ]; then
        while IFS= read -r file; do
            if [ -f "$file" ]; then
                git rm --cached "$file" > /dev/null 2>&1
                rm -f "$file"
                echo "  ✓ 已清理: $file"

                if ! grep -qxF "$file" .gitignore 2>/dev/null; then
                    echo "$file" >> .gitignore
                fi
            fi
        done <<< "$ARCHIVE_FILES"

        # 提交删除和 .gitignore 更新
        git add -A
        if ! git diff --cached --quiet; then
            git commit -m "chore: auto cleanup 待归档 files after sync" --no-verify
            git push origin main
            echo "[auto-sync] 待归档清理完成，GitHub 保留历史版本"
        fi

        # 删除空目录
        find "$ARCHIVE_DIR" -type d -empty -delete 2>/dev/null
        rmdir "$ARCHIVE_DIR" 2>/dev/null || true
    fi
fi
