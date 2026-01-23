#!/bin/bash
set -e  # 遇到错误立即退出

# 获取参数
INPUT_URL="$1"
INPUT_PASS="$2"

# 检查必要参数
if [ -z "$INPUT_URL" ]; then
  echo "Error: URL is required."
  echo "Usage: ./download.sh <url> [password]"
  exit 1
fi

# 检查必要工具
if ! command -v 7z &> /dev/null; then
    echo "Error: 7z could not be found. Please install p7zip-full."
    exit 1
fi

# ==========================================
# 1. 解析 URL 获取文件名 (FILE_NAME)
# ==========================================
clean_url="${INPUT_URL%\?*}"
FILE_NAME=$(basename "$clean_url")

if [ -z "$FILE_NAME" ] || [ "$FILE_NAME" == "/" ]; then
  FILE_NAME="downloaded_file"
fi

echo "Target Filename: $FILE_NAME"

# ==========================================
# 2. 下载文件
# ==========================================
echo "Downloading..."
curl -L -o "$FILE_NAME" "$INPUT_URL"

if [ ! -f "$FILE_NAME" ]; then
  echo "Download failed."
  exit 1
fi

FILE_SIZE=$(stat -c%s "$FILE_NAME" 2>/dev/null || stat -f%z "$FILE_NAME") # 兼容 Linux/Mac stat
echo "File size: $FILE_SIZE bytes"

# ==========================================
# 3. 7z 压缩处理
# ==========================================
CMD_7Z="7z a -mx=1"

# 密码处理
if [ -n "$INPUT_PASS" ]; then
  echo "Password provided. Encrypting..."
  CMD_7Z="$CMD_7Z -p${INPUT_PASS} -mhe=on"
fi

# 分卷处理 (1GB = 1073741824 bytes)
if [ "$FILE_SIZE" -gt 1073741824 ]; then
  echo "File > 1GB. Splitting archive..."
  CMD_7Z="$CMD_7Z -v1g"
fi

ARCHIVE_NAME="${FILE_NAME}.7z"

echo "Compressing..."
# eval 用于正确处理带引号的参数
eval "$CMD_7Z \"$ARCHIVE_NAME\" \"$FILE_NAME\""

# ==========================================
# 4. 导出结果 (兼容本地与GitHub Action)
# ==========================================

# 查找生成的文件列表 (排序以确保顺序)
GENERATED_FILES=$(find . -maxdepth 1 -name "${ARCHIVE_NAME}*" -type f -printf "%f\n" | sort)

# 如果是在 Mac 本地测试，find 命令没有 -printf，使用 ls 替代
if [ -z "$GENERATED_FILES" ]; then
    GENERATED_FILES=$(ls -1 | grep "^${ARCHIVE_NAME}")
fi

echo "----------------------------------------"
echo "Processing Complete."

if [ -n "$GITHUB_ENV" ]; then
    # --- GitHub Action 环境 ---
    echo "Writing to GITHUB_ENV..."
    
    # 写入 FILE_NAME
    echo "FILE_NAME=$FILE_NAME" >> "$GITHUB_ENV"
    
    # 写入 FILE_LIST (多行变量)
    echo "FILE_LIST<<EOF" >> "$GITHUB_ENV"
    echo "$GENERATED_FILES" >> "$GITHUB_ENV"
    echo "EOF" >> "$GITHUB_ENV"
else
    # --- 本地测试环境 ---
    echo "Not in GitHub Actions. Printing variables:"
    echo "FILE_NAME=$FILE_NAME"
    echo "FILE_LIST:"
    echo "$GENERATED_FILES"
fi