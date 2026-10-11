#!/bin/bash
#
# HackintoshDisplayFix — 测试套件
#
# 本工具只能在 macOS 上真正运行，所以这里用 mock 顶替 macOS 专有命令，
# 在 Linux 上验证「解析逻辑 / 交互流程 / 文件产物」是否正确。
#
# 用法：bash tests/run_tests.sh
#

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/HackintoshDisplayFix.sh"
FIX="$HERE/fixtures"
MOCK="$HERE/.mock"
TARGET_DIR="/Library/Displays/Contents/Resources/Overrides"

PASS=0
FAIL=0

# 语言检测在真实 macOS 上首选 `defaults read -g AppleLocale`，测试里用 mock 控制它，
# 避免依赖 Linux 上是否装了中文 locale。
export LANG=C.UTF-8
unset LC_ALL

# 断言里用中文文案，所以默认让 mock 的 AppleLocale 返回 zh_CN；
# test_language 里会用行内赋值覆盖成别的语言。
export HDF_APPLELOCALE=zh_CN

# ---------------------------------------------------------------- 断言

function check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf '  \033[32mPASS\033[0m  %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf '  \033[31mFAIL\033[0m  %s\n' "$desc"
        printf '          期望: %s\n' "$expected"
        printf '          实际: %s\n' "$actual"
        FAIL=$((FAIL + 1))
    fi
}

function check_contains() {
    local desc="$1" needle="$2" hay="$3"
    case "$hay" in
        *"$needle"*)
            printf '  \033[32mPASS\033[0m  %s\n' "$desc"
            PASS=$((PASS + 1)) ;;
        *)
            printf '  \033[31mFAIL\033[0m  %s\n' "$desc"
            printf '          未在输出中找到: %s\n' "$needle"
            printf '          实际输出: %s\n' "$(printf '%s' "$hay" | head -c 400)"
            FAIL=$((FAIL + 1)) ;;
    esac
}

function check_exit() {
    local desc="$1" expected="$2" actual="$3"
    check "$desc" "$expected" "$actual"
}

# ---------------------------------------------------------------- 环境准备

function setup_mocks() {
    rm -rf "$MOCK"
    mkdir -p "$MOCK/bin"

    cat > "$MOCK/bin/uname" <<'EOF'
#!/bin/bash
case "$1" in
    -s) printf 'Darwin\n' ;;
    -m) printf '%s\n' "${HDF_ARCH:-x86_64}" ;;
    *)  printf 'Darwin\n' ;;
esac
EOF

    cat > "$MOCK/bin/ioreg" <<'EOF'
#!/bin/bash
if [ -n "${HDF_IOREG:-}" ] && [ -f "${HDF_IOREG}" ]; then
    cat "$HDF_IOREG"
fi
exit 0
EOF

    # 测试本身以 root 运行，sudo 直接透传；顺带把 macOS 的 wheel 组映射成 root
    cat > "$MOCK/bin/sudo" <<'EOF'
#!/bin/bash
args=()
for a in "$@"; do
    case "$a" in
        -v|--validate) exit 0 ;;
        -n|--non-interactive) continue ;;
    esac
    args+=("${a//root:wheel/root:root}")
done
[ "${#args[@]}" -eq 0 ] && exit 0
exec "${args[@]}"
EOF

    # BSD sed 的 `-i ''` 在 GNU sed 上是错的，这里翻译一下。
    # 在 macOS 上本来就支持 BSD 语法，直接透传 —— 这样 CI 跑 macOS 时
    # 验证的就是脚本里真实的 `sed -i ''` 用法。
    if [ "$(uname -s)" = "Darwin" ]; then
        cat > "$MOCK/bin/sed" <<'EOF'
#!/bin/bash
exec /usr/bin/sed "$@"
EOF
    else
        cat > "$MOCK/bin/sed" <<'EOF'
#!/bin/bash
args=()
skip=0
for a in "$@"; do
    if [ "$skip" = "1" ]; then skip=0; continue; fi
    if [ "$a" = "-i" ]; then args+=("-i"); skip=1; continue; fi
    args+=("$a")
done
exec /usr/bin/sed "${args[@]}"
EOF
    fi

    cat > "$MOCK/bin/defaults" <<'EOF'
#!/bin/bash
# mock：只有 `read -g AppleLocale` 有意义，用 HDF_APPLELOCALE 控制
if [ "$1" = "read" ] && [ -n "${HDF_APPLELOCALE:-}" ]; then
    printf '%s\n' "$HDF_APPLELOCALE"
    exit 0
fi
exit 1
EOF

    # 提权脚本里会 chown root:wheel，Linux 上没有 wheel 组，这里映射成 root:root
    REAL_CHOWN=$(command -v chown)
    cat > "$MOCK/bin/chown" <<EOF
#!/bin/bash
args=()
for a in "\$@"; do
    args+=("\${a//root:wheel/root:root}")
done
exec $REAL_CHOWN "\${args[@]}"
EOF

    # 图标资源：运行时生成，不往仓库里塞假二进制
    mkdir -p "$MOCK/remote/displayIcons"
    cat > "$MOCK/remote/Icons.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>vendors</key>
	<dict>
		<key>VID</key>
		<dict>
			<key>products</key>
			<dict>
				<key>PID</key>
				<dict>
					<key>DisplayIcon</key>
					<string>PICON</string>
					<key>DisplayIconRect</key>
					<string>{{RPX, RPY}, {RPW, RPH}}</string>
					<key>DisplayIsGeneric</key>
					<true/>
					<key>DisplayProductName</key>
					<string>DICON</string>
				</dict>
			</dict>
		</dict>
	</dict>
</dict>
</plist>
PLIST
    for icon_name in iMac MacBook MacBookPro ProDisplayXDR; do
        printf 'icns-mock-%s' "$icon_name" > "$MOCK/remote/displayIcons/${icon_name}.icns"
    done
    printf 'tiff-mock-ProDisplayXDR' > "$MOCK/remote/displayIcons/ProDisplayXDR.tiff"

    # curl：把远端 URL 映射到运行时生成的 $MOCK/remote 下
    cat > "$MOCK/bin/curl" <<EOF
#!/bin/bash
url=""
dest=""
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        -o) dest="\$2"; shift 2 ;;
        -*) shift ;;
        *)  url="\$1"; shift ;;
    esac
done
base="\${url%%/Icons.plist}"
base="\${base%%/displayIcons/*}"
rel="\${url#*\$base/}"
src="$MOCK/remote/\$rel"
[ -z "\$dest" ] && exit 0
if [ -f "\$src" ]; then
    cp "\$src" "\$dest"
    exit 0
fi
exit 22
EOF

    chmod +x "$MOCK/bin/"*
    export PATH="$MOCK/bin:$PATH"
}

function setup_target_root() {
    # 安全防护：测试会清空 $TARGET_DIR。如果你在自己的 Mac 上跑，
    # 那正好是真实显示器配置所在的位置，会把你实际的配置删掉。
    if [ -d "$TARGET_DIR" ] && [ -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
        printf '\n\033[31m拒绝运行。\033[0m\n' >&2
        printf '目录已存在且有内容：%s\n' "$TARGET_DIR" >&2
        printf '测试套件会清空它。为避免破坏你机器上真实的显示器配置，已中止。\n' >&2
        printf '确定要跑的话，请先备份并手动删除该目录。\n\n' >&2
        exit 4
    fi
    LIB_CREATED=0
    [ -e /Library ] || LIB_CREATED=1
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
}

function teardown_target_root() {
    rm -rf "$TARGET_DIR"
    rm -rf "${HOME}/.hackintoshdisplayfix"
    rm -f "${HOME}/.hackintoshdisplayfix-restore.sh"
    if [ "$LIB_CREATED" = "1" ]; then
        rm -rf /Library
    fi
}

# ---------------------------------------------------------------- 测试

function test_syntax() {
    printf '\n\033[1m[1] 语法检查\033[0m\n'
    bash -n "$SCRIPT"
    check "主脚本 bash -n 通过" "0" "$?"
    bash -n "$HERE/run_tests.sh"
    check "测试脚本 bash -n 通过" "0" "$?"
    check "主脚本有正确 shebang" "#!/bin/bash" "$(head -1 "$SCRIPT")"
    check "测试固件齐全" "4" "$(ls "$FIX"/ioreg_intel_*.txt "$FIX"/ioreg_arm64_2.txt 2>/dev/null | wc -l | tr -d ' ')"
}

function test_parse_name() {
    printf '\n\033[1m[2] 显示器名称解析（支持任意 descriptor）\033[0m\n'
    local edid_dell edid_lg name
    edid_dell=$(sed -n 's/.*<\([0-9a-f]*\)>.*/\1/p' "$FIX/ioreg_intel_2.txt" | sed -n '1p')
    edid_lg=$(sed -n 's/.*<\([0-9a-f]*\)>.*/\1/p' "$FIX/ioreg_intel_2.txt" | sed -n '2p')

    name=$( ( source "$SCRIPT"; parse_monitor_name "$edid_dell" ) )
    check "名称在第 3 个 descriptor 时解析正确" "$EXPECT_NAME" "$name"

    name=$( ( source "$SCRIPT"; parse_monitor_name "$edid_lg" ) )
    check "名称在第 4 个 descriptor 时也能解析（旧版会乱码）" "$EXPECT_LG_NAME" "$name"
}

function test_edid_transform() {
    printf '\n\033[1m[3] EDID 改造算法\033[0m\n'
    local edid_dell b64
    edid_dell=$(sed -n 's/.*<\([0-9a-f]*\)>.*/\1/p' "$FIX/ioreg_intel_2.txt" | sed -n '1p')
    b64=$( ( source "$SCRIPT"; build_edid_base64 "$edid_dell" 4268 16771 ) )
    check "base64 与预期一致" "$EXPECT_B64" "$b64"
    check "长度 128 字节编码后为 172 字符" "172" "${#b64}"
}

function test_detect_intel() {
    printf '\n\033[1m[4] Intel 显示器检测\033[0m\n'
    local out
    out=$( HDF_IOREG="$FIX/ioreg_intel_2.txt" bash -c '
        source "'"$SCRIPT"'"
        detect_displays_intel
        printf "%s|%s|%s|%s|%s|%s|%s\n" "$DISP_COUNT" \
            "${DISP_VID[0]}" "${DISP_PID[0]}" "${DISP_NAME[0]}" \
            "${DISP_VID[1]}" "${DISP_PID[1]}" "${DISP_NAME[1]}"' )
    check "检测到 2 台并解析正确" "2|10ac|4183|DELL U2720Q|1e6d|5b11|LG HDR 4K" "$out"
}

function test_detect_arm() {
    printf '\n\033[1m[5] Apple Silicon 显示器检测\033[0m\n'
    local out
    out=$( HDF_ARCH=arm64 HDF_IOREG="$FIX/ioreg_arm64_2.txt" bash -c '
        source "'"$SCRIPT"'"
        detect_displays_arm
        printf "%s|%s|%s|%s|%s|%s\n" "$DISP_COUNT" \
            "${DISP_VID[0]}" "${DISP_PID[0]}" "${DISP_NAME[0]}" \
            "${DISP_VID[1]}" "${DISP_PID[1]}"' )
    check "arm64 检测到 2 台" "2|10ac|4183|DELL U2720Q|1e6d|5b11" "$out"
}

function test_dedupe() {
    printf '\n\033[1m[6] 重复显示器去重\033[0m\n'
    cat "$FIX/ioreg_intel_2.txt" "$FIX/ioreg_intel_1.txt" > "$FIX/.dup.tmp"
    local out
    out=$( HDF_IOREG="$FIX/.dup.tmp" bash -c '
        source "'"$SCRIPT"'"
        detect_displays_intel
        printf "%s" "$DISP_COUNT"' )
    rm -f "$FIX/.dup.tmp"
    check "DELL 重复出现两次只保留一条" "2" "$out"
}

function test_list_cli() {
    printf '\n\033[1m[7] --list 非交互模式\033[0m\n'
    local out rc
    out=$( HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" --list 2>&1 )
    rc=$?
    check_exit "--list 退出码 0" "0" "$rc"
    check_contains "列出 DELL" "10ac:4183" "$out"
    check_contains "列出 DELL 名称" "DELL U2720Q" "$out"
    check_contains "列出 LG" "1e6d:5b11" "$out"
    check_contains "列出 LG 名称" "LG HDR 4K" "$out"
}

function test_no_display() {
    printf '\n\033[1m[8] 无显示器\033[0m\n'
    local out rc
    out=$( HDF_IOREG="$FIX/ioreg_intel_0.txt" bash "$SCRIPT" 2>&1 </dev/null )
    rc=$?
    check_exit "退出码 2" "2" "$rc"
    check_contains "提示未找到显示器" "没有检测到任何显示器" "$out"
}

function test_full_inject() {
    printf '\n\033[1m[9] 完整注入流程（保持原样图标）\033[0m\n'
    local out rc plist
    out=$( printf '1\n1\n6\ny\n' | HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" 2>&1 )
    rc=$?
    check_exit "退出码 0" "0" "$rc"
    plist="$TARGET_DIR/DisplayVendorID-10ac/DisplayProductID-4183"
    check "plist 已写入" "yes" "$([ -f "$plist" ] && echo yes || echo no)"
    if [ -f "$plist" ]; then
        check_contains "plist 含正确 VendorID" "<integer>4268</integer>" "$(cat "$plist")"
        check_contains "plist 含正确 ProductID" "<integer>16771</integer>" "$(cat "$plist")"
        check_contains "plist 含正确 EDID base64" "$EXPECT_B64" "$(cat "$plist")"
    fi
    check_contains "提示修复成功" "显示问题已修复" "$out"
    check_contains "提示重启" "请重启" "$out"
    check_contains "输出确认摘要" "请确认" "$out"
    check_contains "推荐保持原样" "【推荐】" "$out"
}

function test_restore_script() {
    printf '\n\033[1m[10] 还原脚本\033[0m\n'
    local rs="$HOME/.hackintoshdisplayfix-restore.sh"
    check "还原脚本已生成" "yes" "$([ -f "$rs" ] && echo yes || echo no)"
    if [ -f "$rs" ]; then
        bash -n "$rs"
        check "还原脚本语法通过" "0" "$?"
        check_contains "还原脚本含 VID" "VID='10ac'" "$(cat "$rs")"
        check_contains "还原脚本含 PID" "PID='4183'" "$(cat "$rs")"
        check_contains "还原脚本用 bash 而非 sh" "#!/bin/bash" "$(cat "$rs")"
    fi
}

function test_invalid_input_retry() {
    printf '\n\033[1m[11] 非法输入不退出，可重试\033[0m\n'
    local out rc
    out=$( printf '9\nabc\n1\n1\n6\ny\n' | HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" 2>&1 )
    rc=$?
    check_exit "乱输入后仍能跑完" "0" "$rc"
    check_contains "提示输入无效" "输入无效" "$out"
    check_contains "最终仍注入成功" "EDID 注入成功" "$out"
}

function test_cancel() {
    printf '\n\033[1m[12] 取消不产生副作用\033[0m\n'
    local out rc
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    out=$( printf 'q\n' | HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" 2>&1 )
    rc=$?
    check_exit "取消后退出码 0" "0" "$rc"
    check "没有写入任何配置" "no" "$([ -d "$TARGET_DIR/DisplayVendorID-10ac" ] && echo yes || echo no)"
}

function test_restore_one() {
    printf '\n\033[1m[13] 还原：只移除本显示器\033[0m\n'
    local out rc
    # 先注入
    printf '1\n1\n6\ny\n' | HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" >/dev/null 2>&1
    check "注入后配置存在" "yes" "$([ -f "$TARGET_DIR/DisplayVendorID-10ac/DisplayProductID-4183" ] && echo yes || echo no)"
    # 再还原
    out=$( printf '1\n2\n1\ny\n' | HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" 2>&1 )
    rc=$?
    check_exit "还原退出码 0" "0" "$rc"
    check "该显示器配置已移除" "no" "$([ -d "$TARGET_DIR/DisplayVendorID-10ac" ] && echo yes || echo no)"
    check_contains "提示已移除" "配置已移除" "$out"
}

function test_restore_all() {
    printf '\n\033[1m[14] 还原：移除全部\033[0m\n'
    local rc
    printf '1\n1\n6\ny\n' | HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" >/dev/null 2>&1
    printf '1\n2\n2\ny\n' | HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" >/dev/null 2>&1
    rc=$?
    check_exit "还原全部退出码 0" "0" "$rc"
    check "Overrides 目录已删除" "no" "$([ -d "$TARGET_DIR" ] && echo yes || echo no)"
}

function test_language() {
    printf '\n\033[1m[15] 语言切换\033[0m\n'
    local out
    out=$( HDF_APPLELOCALE=zh_CN HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" --list 2>&1 )
    check_contains "中文界面" "检测到 2 台显示器" "$out"

    out=$( HDF_APPLELOCALE=en_US HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" --list 2>&1 )
    check_contains "英文界面" "2 display(s) detected" "$out"

    out=$( HDF_APPLELOCALE=uk_UA HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" --list 2>&1 )
    check_contains "乌克兰语界面" "Знайдено дисплеїв" "$out"

    out=$( HDF_APPLELOCALE=zh_Hans_CN HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" --list 2>&1 )
    check_contains "zh_Hans 也识别为中文" "检测到 2 台显示器" "$out"

    # AppleLocale 取不到时回退到 LANG
    out=$( HDF_APPLELOCALE= LANG=en_US.UTF-8 HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" --list 2>&1 )
    check_contains "无 AppleLocale 时回退 LANG" "display(s) detected" "$out"
}

function test_single_display() {
    printf '\n\033[1m[16] 单显示器也显示列表\033[0m\n'
    local out
    out=$( printf 'q\n' | HDF_IOREG="$FIX/ioreg_intel_1.txt" bash "$SCRIPT" 2>&1 )
    check_contains "单台也列出显示器" "10ac:4183" "$out"
    check_contains "单台也列出名称" "DELL U2720Q" "$out"
}

function test_icon_flow() {
    printf '\n\033[1m[17] 图标流程（iMac）\033[0m\n'
    local rc
    rm -rf "$TARGET_DIR"; mkdir -p "$TARGET_DIR"
    printf '1\n1\n1\ny\n' | HDF_IOREG="$FIX/ioreg_intel_2.txt" bash "$SCRIPT" >/dev/null 2>&1
    rc=$?
    check_exit "带图标注入退出码 0" "0" "$rc"
    check "icns 已写入" "yes" "$([ -f "$TARGET_DIR/DisplayVendorID-10ac/DisplayProductID-4183.icns" ] && echo yes || echo no)"
    check "Icons.plist 已写入" "yes" "$([ -f "$TARGET_DIR/Icons.plist" ] && echo yes || echo no)"
    if [ -f "$TARGET_DIR/Icons.plist" ]; then
        local c
        c=$(cat "$TARGET_DIR/Icons.plist")
        check_contains "Icons.plist 占位符 VID 已替换" "10ac" "$c"
        case "$c" in
            *PLACEHOLDER*|*VID*) check "Icons.plist 无残留占位符" "clean" "残留" ;;
            *) check "Icons.plist 无残留占位符" "clean" "clean" ;;
        esac
    fi
}

function test_help_version() {
    printf '\n\033[1m[18] --help / --version\033[0m\n'
    local out rc
    out=$( bash "$SCRIPT" --version 2>&1 )
    check "版本号" "HackintoshDisplayFix 1.0.0" "$out"
    out=$( bash "$SCRIPT" --help 2>&1 )
    rc=$?
    check_exit "--help 退出码 0" "0" "$rc"
    check_contains "--help 含用法" "用法" "$out"
    check_contains "--help 含标语（验证语言已先加载）" "修复黑苹果" "$out"
}

# ---------------------------------------------------------------- 主流程

LIB_CREATED=0
setup_mocks
setup_target_root

# 载入预期值
. "$FIX/expected.sh"

printf '\n\033[1m=== HackintoshDisplayFix 测试套件 ===\033[0m\n'
printf '脚本: %s\n' "$SCRIPT"

test_syntax
test_parse_name
test_edid_transform
test_detect_intel
test_detect_arm
test_dedupe
test_list_cli
test_no_display
test_full_inject
test_restore_script
test_invalid_input_retry
test_cancel
test_restore_one
test_restore_all
test_language
test_single_display
test_icon_flow
test_help_version

teardown_target_root

printf '\n\033[1m=== 结果 ===\033[0m\n'
printf '  通过: \033[32m%d\033[0m\n' "$PASS"
printf '  失败: \033[31m%d\033[0m\n' "$FAIL"
printf '\n'

[ "$FAIL" -eq 0 ] || exit 1
exit 0
