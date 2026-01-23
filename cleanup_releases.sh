#!/bin/bash
set -e

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "🚀 DRY RUN MODE: 模拟模式，不会执行删除"
fi

echo "正在获取 Release 列表..."

# 1. 先获取所有 tagName 和 createdAt
# gh release list 默认不包含 body 字段，所以我们分两步走
RELEASES=$(gh release list --limit 1000 --json tagName,createdAt)

# 获取当前时间戳
NOW_TS=$(date +%s)

# 遍历 Release
echo "$RELEASES" | jq -c '.[]' | while read -r row; do
    tag_name=$(echo "$row" | jq -r '.tagName')
    created_at=$(echo "$row" | jq -r '.createdAt')

    echo "🔍 检查 Release: $tag_name (创建时间: $created_at)"

    # 2. 通过 gh release view 获取该 tag 的详细 body (JSON 格式输出)
    # --json body 专门提取 body 字段
    body_content=$(gh release view "$tag_name" --json body -q '.body' 2>/dev/null || echo "")

    if [[ -z "$body_content" ]]; then
        echo "   ⏭️  [跳过] 无法获取描述内容"
        continue
    fi

    # 3. 解析 body 中的 expire_days
    # 使用 try/catch 或简单的 jq 判断 body 是否为合法 JSON
    expire_days=$(echo "$body_content" | jq -r 'try .expire_days catch empty' 2>/dev/null)

    if [[ -z "$expire_days" ]] || [[ "$expire_days" == "null" ]]; then
        echo "   ⏭️  [跳过] 描述不是有效 JSON 或缺少 expire_days"
        continue
    fi

    # 4. 日期计算
    created_ts=$(date -d "$created_at" +%s)
    expire_seconds=$((expire_days * 86400))
    expiration_ts=$((created_ts + expire_seconds))

    if [ "$NOW_TS" -gt "$expiration_ts" ]; then
        echo "   🗑️  [删除] 已过期 $expire_days 天"
        if [ "$DRY_RUN" = false ]; then
            gh release delete "$tag_name" --cleanup-tag -y
            echo "      ✅ 已执行删除"
        else
            echo "      (Dry Run: 跳过删除命令)"
        fi
    else
        days_left=$(( (expiration_ts - NOW_TS) / 86400 ))
        echo "   ✅ [保留] 剩余有效期约 $days_left 天"
    fi

    echo "--------------------------------"
done