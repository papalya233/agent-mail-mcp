#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# chroot 内 /etc 与 PREFIX/etc 指向同一个目录；不用可继承的标记冒充检测。
if ! [ /etc -ef "${PREFIX:?请在 Termux 中启动}/etc" ]; then
    exec termux-chroot sh "$HERE/start-termux.sh" "$@"
fi
export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
exec python3 "$HERE/mail_mcp.py" --config "${1:-$HERE/config.json}"
