#!/bin/bash
set -e

# 如果没有传入 dry-run 参数，默认为 false (真实删除)
# 使用: ./cleanup_releases.sh --dry-run
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "🚀 DRY RUN MODE: 不会执行真实删除操作"
fi

echo "正在获取 Release 列表..."

# 使用 gh cli 获取 release 信息
# limit 1000 防止 release 太多取不全
# json 字段: tagName(标签), createdAt(创建时间), body(描述内容)
RELEASES_JSON=$(gh release list --limit 1000 --json tagName,createdAt,body)

# 获取当前时间戳
NOW_TS=$(date +%s)

# 使用 jq 解析并遍历每一条 release
# 注意：这里使用 base64 编码传递数据，防止特殊字符破坏循环结构
echo "$RELEASES_JSON" | jq -r '.[] | @base64' | while read -r encoded_release; do
    
    # 解码
    _release=$(echo "$encoded_release" | base64 --decode)
    
    tag_name=$(echo "$_release" | jq -r '.tagName')
    created_at=$(echo "$_release" | jq -r '.createdAt')
    body_content=$(echo "$_release" | jq -r '.body')

    # 1. 尝试解析 body 中的 expire_days
    # 如果 body 不是 json，或者没有 expire_days，结果将为空或 null
    expire_days=$(echo "$body_content" | jq -r '.expire_days // empty' 2>/dev/null)

    # 如果无法提取 expire_days，跳过该 release
    if [[ -z "$expire_days" ]] || [[ "$expire_days" == "null" ]]; then
        echo "⏭️  [跳过] $tag_name: 描述中未找到有效 expire_days"
        continue
    fi

    # 验证 expire_days 是否为数字
    if ! [[ "$expire_days" =~ ^[0-9]+$ ]]; then
        echo "⚠️  [跳过] $tag_name: expire_days ($expire_days) 不是有效数字"
        continue
    fi

    # 2. 计算过期时间
    # 将 ISO 8601 时间转为 Unix 时间戳
    created_ts=$(date -d "$created_at" +%s)
    # 计算过期秒数 (days * 24 * 60 * 60)
    expire_seconds=$((expire_days * 86400))
    # 计算到期时间戳
    expiration_ts=$((created_ts + expire_seconds))

    # 3. 比较并删除
    if [ "$NOW_TS" -gt "$expiration_ts" ]; then
        echo "🗑️  [删除] $tag_name (创建于: $created_at, 有效期: $expire_days 天, 已过期)"
        
        if [ "$DRY_RUN" = false ]; then
            # 真实删除 release，--cleanup-tag 同时删除对应的 git tag
            gh release delete "$tag_name" --cleanup-tag -y
        else
            echo "    (Dry Run: 模拟执行删除命令)"
        fi
    else
        echo "✅ [保留] $tag_name (将在 $(date -d @$expiration_ts '+%Y-%m-%d %H:%M:%S') 过期)"
    fi

done