#!/bin/bash

script_url="https://install.lifebus.top/app_install.sh"

echo "Downloading and executing script from $script_url..."
bash <(curl -sL "$script_url")

echo "Script execution completed."

### Personal 1Panel App Store

script_url="https://raw.githubusercontent.com/talentestors/appstore-1panel/refs/heads/main/install_app.sh"

echo "Downloading and executing script from $script_url..."

bash <(curl -sL "$script_url")

echo "Script execution completed."

#############################################
# 用户需填写的变量
#############################################

API_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
PANEL_HOST="localhost"
PANEL_PORT="1111"

# 两个接口地址（不用动）
API_SYNC_LOCAL="/api/v2/apps/sync/local"
API_READ_FILE="/api/v2/files/read"

#############################################
# 工具函数
#############################################

# 生成 UUID（Linux 通用方法）
gen_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 生成 token
gen_token() {
    local ts=$(date +%s)
    local tk=$(echo -n "1panel${API_KEY}${ts}" | md5sum | awk '{print $1}')
    echo "${tk},${ts}"
}

# 判断系统是否有 jq
HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
    HAS_JQ=1
fi

#############################################
# 主逻辑开始
#############################################

TASK_ID=$(gen_uuid)
echo "📌 生成 Task ID: ${TASK_ID}"
echo ""

TOKEN_INFO=$(gen_token)
TOKEN=$(echo "$TOKEN_INFO" | cut -d',' -f1)
TIMESTAMP=$(echo "$TOKEN_INFO" | cut -d',' -f2)

echo "📌 时间戳: $TIMESTAMP"
echo "📌 Token: $TOKEN"
echo ""

#################################################
# STEP 1 — 触发同步任务
#################################################
echo "🚀 STEP 1: 调用接口 1 开始同步任务..."
echo "POST http://${PANEL_HOST}:${PANEL_PORT}${API_SYNC_LOCAL}"

RESP1=$(curl -s -X POST "http://${PANEL_HOST}:${PANEL_PORT}${API_SYNC_LOCAL}" \
    -H "1Panel-Token: ${TOKEN}" \
    -H "1Panel-Timestamp: ${TIMESTAMP}" \
    -H "Content-Type: application/json" \
    -d "{\"taskID\":\"${TASK_ID}\"}")

echo "返回内容：$RESP1"
echo ""

CODE1=$(echo "$RESP1" | grep -o '"code":[0-9]*' | cut -d: -f2)
if [ "$CODE1" != "200" ]; then
    echo "❌ 启动任务失败，停止执行！"
    exit 1
fi

echo "✅ 任务启动成功！"
echo ""
