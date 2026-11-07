#!/data/data/com.termux/files/usr/bin/bash
# Agent Mail 邮件工具：安卓 Termux 一键安装。
# 用法（通讯录每个人写成「名字 邮箱」，用引号括起来）：
#   curl -fsSL https://cdn.jsdelivr.net/gh/papalya233/agent-mail-mcp@main/install-termux.sh -o install.sh
#   bash install.sh "朋友 friend@agent.qq.com" "另一个朋友 other@agent.qq.com"
# 每样东西先试原地址，10 秒连不上就换国内能连上的（jsDelivr、npmmirror）；命令行程序照旧核对指纹。
# 再跑一次就是「改通讯录」：口令和登录都会保留。
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/papalya233/agent-mail-mcp/main"
REPO_CDN="https://cdn.jsdelivr.net/gh/papalya233/agent-mail-mcp@main"
CLI_VERSION="1.0.18"
NPM_PATH="@tencent-qqmail/agently-cli-linux-arm64/-/agently-cli-linux-arm64-${CLI_VERSION}.tgz"
CLI_SHA256="84a90737baaaba8da3d2584c3c71eaa5afb1f4613bf13f3038e3c58f1c28c0f2"
APP="$HOME/agent-mail"
WORKSPACE="${AGENT_MAIL_WORKSPACE:-agent}"
PORT="${AGENT_MAIL_PORT:-8811}"

step() { printf '\n== %s\n' "$*"; }
# fetch 存成的文件 地址1 地址2 …：一个个试，10 秒连不上就换下一个
fetch() {
  local out=$1 url host; shift
  for url in "$@"; do
    host=$(printf '%s' "$url" | cut -d/ -f3)
    printf '  从 %s 下载 %s …\n' "$host" "$(basename "$out")"
    if curl -fsSL --connect-timeout 10 --max-time 300 -o "$out" "$url"; then return 0; fi
    printf '  %s 连不上，换一个\n' "$host"
  done
  return 1
}
fail() { printf '\n!! %s\n' "$*"; exit 1; }

[ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] || fail "请在安卓的 Termux 里运行这个脚本。"
[ "$(uname -m)" = "aarch64" ] || fail "这台手机不是 64 位（$(uname -m)），这个工具用不了。"
[ $# -ge 1 ] || fail '要带上通讯录，比如：bash install.sh "朋友 friend@agent.qq.com"'

step "1/6 安装要用的工具（第一次会久一点）"
pkg update -y >/dev/null 2>&1 || true
pkg install -y python curl proot ca-certificates tmux >/dev/null

step "2/6 下载腾讯 Agent Mail 的命令行（核对文件指纹）"
mkdir -p "$APP/bin"
cd "$APP"
if [ ! -x "$APP/bin/agently-cli" ]; then
  fetch cli.tgz "https://registry.npmjs.org/$NPM_PATH" "https://registry.npmmirror.com/$NPM_PATH" || fail "命令行程序下载不下来，检查一下网络再跑一次。"
  echo "${CLI_SHA256}  cli.tgz" | sha256sum -c - >/dev/null 2>&1 || { rm -f cli.tgz; fail "下载的文件指纹对不上，已删掉，没有安装。"; }
  tar xzf cli.tgz
  mv package/bin/agently-cli bin/agently-cli
  chmod +x bin/agently-cli
  rm -rf package cli.tgz
fi
"$APP/bin/agently-cli" --version

step "3/6 下载邮件工具"
fetch mail_mcp.py "$REPO_RAW/mail_mcp.py" "$REPO_CDN/mail_mcp.py" || fail "邮件工具下载不下来，检查一下网络再跑一次。"
fetch start-termux.sh "$REPO_RAW/start-termux.sh" "$REPO_CDN/start-termux.sh" || fail "启动脚本下载不下来，检查一下网络再跑一次。"

step "4/6 写配置和通讯录"
python3 - "$APP" "$WORKSPACE" "$PORT" "$@" <<'PY'
import json, os, re, secrets, sys
app, workspace, port, *people = sys.argv[1:]
contacts = []
for item in people:
    name, _, email = item.strip().rpartition(' ')
    if not name.strip() or not re.fullmatch(r'[^\s,;<>@]+@[^\s,;<>@]+', email):
        sys.exit(f'!! 通讯录这一项不对：「{item}」，要写成「名字 邮箱」')
    contacts.append({'name': name.strip(), 'email': email, 'note': ''})
path = os.path.join(app, 'config.json')
old = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
config = {'listen': '127.0.0.1', 'port': int(port),
          'token': old.get('token') or secrets.token_urlsafe(32),
          'cli': os.path.join(app, 'bin', 'agently-cli'),
          'env': {'AGENTLY_WORKSPACE': workspace},
          'contacts': contacts, 'max_body_chars': 8000, 'notify': {'url': '', 'secret': ''}}
with open(path, 'w', encoding='utf-8') as handle:
    json.dump(config, handle, ensure_ascii=False, indent=2)
os.chmod(path, 0o600)
print('通讯录：' + '、'.join(f"{c['name']}（{c['email']}）" for c in contacts))
PY

step "5/6 登录邮箱"
run_cli() {
  termux-chroot sh -c "export SSL_CERT_FILE=\"\$PREFIX/etc/tls/cert.pem\" AGENTLY_WORKSPACE='$WORKSPACE' AGENTLY_DISABLE_TELEMETRY=1 AGENTLY_CLI_NO_UPDATE_NOTIFIER=1; '$APP/bin/agently-cli' $*"
}
if run_cli auth status 2>/dev/null | grep '"logged_in": true' >/dev/null; then
  echo "已经登录过了，跳过。"
else
  echo "马上会出现一个链接："
  echo "  1. 复制这个链接，在【电脑】的浏览器里打开；"
  echo "  2. 用手机微信【扫一扫】对着电脑屏幕扫（从相册识别不行）；"
  echo "  3. 在「授权接入使用的邮箱」页上，选「新建邮箱地址并绑定」，给它起个地址，再点确定。"
  echo "  不要选已经绑了别的机的地址，选了会把那边顶掉。"
  run_cli auth login || fail "登录没成功（可能是链接过期了）。不用着急，再跑一次这个脚本就行。"
fi
run_cli +me | grep -E '"email"' || true

step "6/6 启动"
cat > "$APP/start.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock 2>/dev/null || true
if tmux has-session -t mail 2>/dev/null; then echo "邮件工具已经在跑了。"; exit 0; fi
tmux new-session -d -s mail "sh '$APP/start-termux.sh' '$APP/config.json'"
sleep 2
if tmux has-session -t mail 2>/dev/null; then echo "邮件工具启动了（tmux 里叫 mail 的那个窗口）。"; else echo "启动失败：敲 sh '$APP/start-termux.sh' '$APP/config.json' 看看报什么错。"; fi
EOF
chmod +x "$APP/start.sh"
grep -q "alias mail-start=" "$HOME/.bashrc" 2>/dev/null || echo "alias mail-start='bash $APP/start.sh'" >> "$HOME/.bashrc"
tmux kill-session -t mail 2>/dev/null || true
bash "$APP/start.sh"

TOKEN=$(python3 -c "import json;print(json.load(open('$APP/config.json'))['token'])")
step "装好了！在北极星里添加一个 MCP 服务器，填这两样："
echo "  地址：http://127.0.0.1:$PORT/mcp"
echo "  请求头：Authorization: Bearer $TOKEN"
echo
echo "以后手机重启了、或者 Termux 被关了，打开 Termux 敲 mail-start 就能再开起来。"
echo "要改通讯录，就带上新的名单再跑一次这个脚本。"
