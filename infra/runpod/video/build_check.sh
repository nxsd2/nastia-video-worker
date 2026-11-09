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
# Обработчик: наш поверх стокового импортируется (runpod, websocket — из venv образа).
if ! (cd / && python -c "import handler, comfy_stock_handler; assert handler.stock is comfy_stock_handler; assert callable(comfy_stock_handler.handler)"); then
  echo "build_check: наш обработчик не импортируется"
  exit 1
fi
# SageAttention 2: пакет и расширения CUDA импортируются без видеокарты (libcuda не нужна),
# ядра под sm_89 и sm_120 сверены cuobjdump на ступени sage-build. Флаг ComfyUI
# --use-sage-attention в стоковом start.sh подставляется через NASTIA_COMFY_ARGS.
if ! (cd / && python - <<'PY'
import importlib.metadata as md
import sageattention, sageattention.core as core
from sageattention import _fused, _qattn_sm80, _qattn_sm89
assert core.SM80_ENABLED and core.SM89_ENABLED, "sm80/sm89 compile modules not loaded"
print("build_check: sageattention", md.version("sageattention"))
PY
); then
  echo "build_check: SageAttention не импортируется"
  exit 1
fi
# ComfyUI видит sage: функция `sage` в реестре внимания ядра (её берёт узел
# NastiaAttentionBackend) — иначе узел на поде упадёт.
if ! (cd /comfyui && python - <<'PY'
import sys
# Как main.py: без enable_args_parsing() cli_args берёт parse_args([]) и --cpu не
# действует — на раннере без видеокарты model_management падает на torch.cuda.
sys.argv = ["main.py", "--cpu"]
import comfy.options
comfy.options.enable_args_parsing()
import comfy.ldm.modules.attention as a
assert a.SAGE_ATTENTION_IS_AVAILABLE and "sage" in a.REGISTERED_ATTENTION_FUNCTIONS, sorted(a.REGISTERED_ATTENTION_FUNCTIONS)
print("build_check: внимание ComfyUI:", ", ".join(sorted(a.REGISTERED_ATTENTION_FUNCTIONS)))
PY
); then
  echo "build_check: ComfyUI не видит sageattention"
  exit 1
fi
grep -q -- '--log-stdout ${NASTIA_COMFY_ARGS:-} &$' /start.sh || { echo "build_check: в start.sh нет NASTIA_COMFY_ARGS"; exit 1; }
cd /comfyui && echo "build_check: ок, ComfyUI $(git describe --tags 2>/dev/null)"
rm -f "$log"
