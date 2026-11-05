#!/bin/bash
# Проверка образа на сборке (RUN в Dockerfile): ComfyUI стартует на CPU и грузит пакеты
# узлов. Нужный пакет не загрузился — сборка падает. Узлы RTX без nvidia-vfx (ставится на
# старте воркера) здесь не грузятся — это ожидаемо, их проверяет старт на видеокарте.
set -uo pipefail
cd /comfyui
log=$(mktemp)
timeout 600 python main.py --quick-test-for-ci --cpu >"$log" 2>&1
status=$?
grep -E "seconds( \(IMPORT FAILED\))?: /comfyui/custom_nodes/" "$log" || true
if [ $status -ne 0 ]; then
  tail -60 "$log"
  echo "build_check: ComfyUI не стартовал (код $status)"
  exit 1
fi
failed=0
for pack in gguf ComfyUI_essentials ComfyUI-VideoHelperSuite nastia_video_nodes; do
  if ! grep -qE "seconds: /comfyui/custom_nodes/$pack\$" "$log"; then
    echo "build_check: пакет $pack не загрузился"
    failed=1
  fi
done
for f in rife47 rife49; do
  [ -s "/comfyui/custom_nodes/nastia_video_nodes/fill/nodes/cache/rife_models/$f.pth" ] || { echo "build_check: нет весов $f"; failed=1; }
done
[ -d /comfyui/custom_nodes/Nvidia_RTX_Nodes_ComfyUI ] || { echo "build_check: нет узлов RTX"; failed=1; }
if [ $failed -ne 0 ]; then
  grep -iE "error|traceback|cannot import|No module" "$log" | head -40
  exit 1
fi
cd /comfyui && echo "build_check: ок, ComfyUI $(git describe --tags 2>/dev/null)"
rm -f "$log"
