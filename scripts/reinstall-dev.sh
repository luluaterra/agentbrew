#!/bin/bash
# AgentBrew Dev 本地重装脚本。
#
# 用途：重建后把 Debug App 装回 /Applications 并保持 daemon 一致。
# 设计目标：把管理员授权弹窗降到必要时的最少一次——SMAppService 注册
# 特权 daemon 必须弹窗（Apple 安全模型，无法绕过），但只有嵌入的
# daemon 二进制真正变化时才需要注册；纯界面改动（汉化、面板等）零密码。
#
# 用法：scripts/reinstall-dev.sh [--clean]
#   --clean  先 clean 再构建（plist/资源结构变化导致 bundle 签名失效时用）

set -euo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/AgentBrew Dev.app"
SRC_APP="$HOME/Library/Developer/Xcode/DerivedData/LetItBrew-amffrpaijinplhcvrimnxyzngyro/Build/Products/Debug/AgentBrew Dev.app"
HASH_FILE="/tmp/agentbrew-registered-daemon-cdhash.txt"

export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"

echo "==> 自检：L10n 映射表重复键扫描"
python3 - <<'LINT'
import re, sys
src = open('Sources/LetItBrewApp/Localization.swift').read()
start = src.index('private static let exact')
end = src.index('private static let patterns')
keys = re.findall(r'^\s{8}"((?:[^"\\]|\\.)*)":', src[start:end], re.M)
dupes = {k for k in keys if keys.count(k) > 1}
if dupes:
    print("!! L10n.exact 存在重复键（会导致启动崩溃）:", list(dupes)[:3])
    sys.exit(1)
print("   L10n.exact", len(keys), "键，无重复")
LINT

echo "==> 构建（$([ "${1:-}" = "--clean" ] && echo clean || echo incremental)）"
if [ "${1:-}" = "--clean" ]; then
    xcodebuild -scheme LetItBrew -configuration Debug clean build -quiet
else
    xcodebuild -scheme LetItBrew -configuration Debug build -quiet
fi

codesign -v "$SRC_APP" || { echo "!! 构建产物签名无效（增量构建改动过资源时用 --clean）"; exit 1; }

# codesign 的详细信息走 stderr。
NEW_CDHASH=$(codesign -dvvv "$SRC_APP/Contents/Library/LaunchServices/AgentBrewDaemon" 2>&1 | awk '/CDHash=/ {print $NF}')

echo "==> 退出旧实例并替换 App"
osascript -e 'tell application "AgentBrew Dev" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$APP"
cp -R "$SRC_APP" /Applications/
codesign -v "$APP"

OLD_CDHASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")
if [ "$NEW_CDHASH" = "$OLD_CDHASH" ] && [ -n "$OLD_CDHASH" ]; then
    echo "==> daemon 二进制未变化（cdhash 一致），跳过重新注册——零密码"
else
    echo "==> daemon 已变化，重新注册（会弹一次管理员授权）"
    "$APP/Contents/MacOS/AgentBrew" --register-daemon
    echo "$NEW_CDHASH" > "$HASH_FILE"
fi

echo "==> 启动"
open "$APP"
sleep 6
if pmset -g assertions | grep -qi "AgentBrew"; then
    echo "==> ✅ 完成：AgentBrew Dev 正在运行并持有防睡眠断言"
else
    echo "==> ✅ 完成：AgentBrew Dev 正在运行（当前无 working 会话，无断言属正常）"
fi
