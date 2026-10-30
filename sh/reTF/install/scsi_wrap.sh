#!/data/data/com.termux/files/usr/bin/bash
EXE="$HOME/scsi_dump"
if [ $# -lt 1 ]; then
    echo "用法: $0 [scsi_dump参数...] <fd>" >&2
    exit 1
fi
FD="${!#}"
if [ $# -gt 1 ]; then
    ARGS=("${@:1:$(( $# - 1 ))}")
else
    ARGS=()
fi
echo "[wrapper] fd=$FD  参数: ${ARGS[*]}" >&2
exec "$EXE" "$FD" "${ARGS[@]}"
