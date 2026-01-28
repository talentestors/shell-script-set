#!/bin/bash
echo "XFS-智能碎片整理"
MOUNT_POINT="/extra"
FRAG_THRESHOLD=15
EXTENTS_THRESHOLD=1.6  # 平均extents数量阈值

# 获取设备路径
DEVICE=$(df -P "$MOUNT_POINT" | awk 'NR==2{print $1}')
[ -z "$DEVICE" ] && { echo "$(date): Error: Cannot find device for $MOUNT_POINT"; exit 1; }

# 获取详细碎片化信息
FRAG_OUTPUT=$(sudo xfs_db -c "frag -f" -r "$DEVICE" 2>/dev/null)
EXTENTS_OUTPUT=$(sudo xfs_db -c "fi" -r "$DEVICE" 2>/dev/null | grep "average" | head -1)

# 提取平均extents数量（更可靠的指标）
AVG_EXTENTS=$(echo "$EXTENTS_OUTPUT" | awk -F'extents per file' '{print $1}' | awk '{print $NF}' | tr -d '[:space:]')
[ -z "$AVG_EXTENTS" ] && AVG_EXTENTS="1.00"

# 提取碎片化百分比（作为辅助参考）
FRAG_PERCENT=$(echo "$FRAG_OUTPUT" | awk -F'fragmentation factor ' '{print $2}' | awk -F'%' '{print $1}' | tr -d ' ')
[ -z "$FRAG_PERCENT" ] && FRAG_PERCENT="0.00"

echo "$(date): Device: $DEVICE | Fragmentation: ${FRAG_PERCENT}% | Avg Extents: ${AVG_EXTENTS} | Thresholds: Frag>${FRAG_THRESHOLD}%, Extents>${EXTENTS_THRESHOLD}"

# 使用 awk 进行浮点数比较（不依赖 bc）
NEED_DEFRAG=$(awk -v avg="$AVG_EXTENTS" -v threshold="$EXTENTS_THRESHOLD" 'BEGIN { if (avg + 0 > threshold + 0) print 1; else print 0 }')

if [ "$NEED_DEFRAG" -eq 1 ]; then
    echo "$(date): ⚠️ HIGH FRAGMENTATION DETECTED! Avg extents (${AVG_EXTENTS}) exceeds threshold (${EXTENTS_THRESHOLD})"
    echo "$(date): Running defragmentation on $MOUNT_POINT..."
    sudo xfs_fsr -v "$MOUNT_POINT" | tee -a /var/log/xfs_defrag_$(date +%Y%m%d).log
    DEF_EXIT_CODE=$?
    [ $DEF_EXIT_CODE -ne 0 ] && echo "$(date): Warning: xfs_fsr exited with code $DEF_EXIT_CODE"
else
    echo "$(date): ✅ OPTIMAL FRAGMENTATION LEVEL: Avg extents (${AVG_EXTENTS}) is below threshold (${EXTENTS_THRESHOLD})"
    echo "$(date): No defragmentation needed."
fi

echo "$(date): [SCRIPT-COMPLETED] Mount: $MOUNT_POINT | Final Avg Extents: ${AVG_EXTENTS}"
exit 0