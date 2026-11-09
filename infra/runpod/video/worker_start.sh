# Старт воркера полигона видео: модели из кэша моделей RunPod (HF-репо nexside/nastia-video)
# → папки ComfyUI. Два способа запуска:
# * свой образ ghcr.io/nexsidee/nastia-video-worker (infra/runpod/video/Dockerfile) — CMD
#   образа `bash /nastia/worker_start.sh` (dockerArgs шаблона — пусто);
# * стоковый runpod/worker-comfyui:5.10.0-base-cuda12.8.1 — этот текст целиком в
#   dockerStartCmd шаблона «nastia-video-worker» (как было до своего образа).
#
# Как у Krea (infra/runpod/krea2/worker_start.sh), отличия:
# + папки видео-моделей: clip_vision (Wan 2.1 i2v), audio_encoders (звук H3 и
#   речевые ворклоу), upscale_models / latent_upscale_models (повышение
#   разрешения), model_patches. GGUF (LoaderGGUF) берёт файлы из diffusion_models:
#   его папка `model_gguf` — те же пути, что у diffusion_models (models/unet и
#   models/diffusion_models), `get_full_path('unet')` ядро сводит к diffusion_models;
# + ComfyUI обновляется до COMFYUI_REF (тег; v0.43.0 несёт узлы Wan 2.2 — nodes_wan.py —
#   и MiniMax H3 — nodes_minimax_h3.py), стоковый образ 5.10.0 — 0.34. Свой образ уже
#   на теге (NASTIA_COMFYUI_BAKED_REF) — шаг пропускается;
# + RTX Video (узлы Nvidia_RTX_Nodes_ComfyUI, только в своём образе): nvidia-vfx и
#   запасная libnvidia-ngx ставятся здесь, а не в образе (лицензия NVIDIA не даёт их
#   распространять в публичном образе) — из папки `runtime/` кэша моделей, иначе с
#   серверов NVIDIA; sha256 сверяется. Потом прогрев эффекта в фоне (первая загрузка
#   16–22 с — компиляция в кэш CUDA; дальше 0,3 с);
# − имена файлов моделей в журнал воркера не печатаются (LoRA и модели — содержимое
#   владельца): только число файлов в каждой папке.
REPO_CACHE=/runpod-volume/huggingface-cache/hub/models--nexside--nastia-video
SNAP=$(ls -dt "$REPO_CACHE"/snapshots/*/ 2>/dev/null | head -1)
echo "video: snapshot=$(basename "${SNAP:-НЕТ}")"
if [ -z "$SNAP" ]; then ls -la /runpod-volume /runpod-volume/huggingface-cache/hub 2>&1 | head -20; fi
for d in diffusion_models checkpoints loras text_encoders vae clip_vision audio_encoders upscale_models latent_upscale_models model_patches; do
  mkdir -p /comfyui/models/$d
  n=0
  if [ -n "$SNAP" ] && [ -d "$SNAP$d" ]; then
    for f in "$SNAP$d"/*; do
      [ -e "$f" ] || continue
      ln -sf "$f" /comfyui/models/$d/ && n=$((n + 1))
    done
  fi
  echo "video: $d — файлов: $n"
done
if [ -n "$COMFYUI_REF" ] && [ "$COMFYUI_REF" = "${NASTIA_COMFYUI_BAKED_REF:-}" ]; then
  echo "video: ComfyUI $COMFYUI_REF — уже в образе"
elif [ -n "$COMFYUI_REF" ] && [ -d /comfyui/.git ]; then
  t0=$(date +%s)
  cd /comfyui \
    && git fetch -q --depth 1 origin "refs/tags/$COMFYUI_REF:refs/tags/$COMFYUI_REF" \
    && git -c advice.detachedHead=false checkout -q "$COMFYUI_REF" \
    && uv pip install -q --python /opt/venv/bin/python -r /comfyui/requirements.txt \
    && echo "video: ComfyUI -> $COMFYUI_REF за $(( $(date +%s) - t0 )) с" \
    || echo "video: обновить ComfyUI до $COMFYUI_REF не удалось — работаю на версии образа"
  cd /
fi

# ── RTX Video (только свой образ) ────────────────────────────────────────────
VFX_WHL=nvidia_vfx-0.2.0.0-cp312-abi3-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl
VFX_SHA256=0252866a7b798a6f92c8543443d88f716e8c5bbc6a7ddd77a2754728dada9fa8
NGX_DRIVER=580.95.05
NGX_RUN_SHA256=849ef0ef8e842b9806b2cde9f11c1303d54f1a9a769467e4e5d961b2fe1182a7
NGX_LIB=/usr/lib/x86_64-linux-gnu/libnvidia-ngx.so.1
PY=/opt/venv/bin/python

sha_ok() { echo "$2  $1" | sha256sum -c --status - ; }

rtx_vfx() {
  "$PY" -c "import importlib.util as u, sys; sys.exit(0 if u.find_spec('nvvfx') else 1)" 2>/dev/null && return 0
  local t0 src
  t0=$(date +%s)
  src="${SNAP}runtime/$VFX_WHL"
  if ! { [ -n "$SNAP" ] && [ -e "$src" ] && sha_ok "$src" "$VFX_SHA256"; }; then
    src="/tmp/$VFX_WHL"
    wget -q -O "$src" "https://pypi.nvidia.com/nvidia-vfx/$VFX_WHL" && sha_ok "$src" "$VFX_SHA256" \
      || { echo "video: rtx — nvidia-vfx не скачался или sha256 не сошёлся, узлы RTX не загрузятся"; rm -f "$src"; return 1; }
  fi
  uv pip install -q --no-deps --python "$PY" "$src" \
    && echo "video: rtx — nvidia-vfx 0.2.0.0 за $(( $(date +%s) - t0 )) с" \
    || { echo "video: rtx — nvidia-vfx не поставился"; return 1; }
  case "$src" in /tmp/*) rm -f "$src" ;; esac
}

rtx_ngx() {
  # NGX драйвера монтирует NVIDIA Container Toolkit (право `ngx` — NVIDIA_DRIVER_CAPABILITIES=all).
  # Нет — запасная из драйвера 580.95.05 (проверено: работает и на драйвере 595). Ссылкой в
  # системную папку, а НЕ в LD_LIBRARY_PATH: иначе запасная подменила бы родную.
  [ -e "$NGX_LIB" ] && { echo "video: rtx — NGX драйвера на месте"; return 0; }
  local t0 lib run
  t0=$(date +%s)
  lib=/opt/ngx/libnvidia-ngx.so.$NGX_DRIVER
  mkdir -p /opt/ngx
  if [ -n "$SNAP" ] && [ -e "${SNAP}runtime/libnvidia-ngx.so.$NGX_DRIVER" ]; then
    cp "${SNAP}runtime/libnvidia-ngx.so.$NGX_DRIVER" "$lib"
  else
    run=/tmp/nv-$NGX_DRIVER.run
    wget -q -O "$run" "https://us.download.nvidia.com/XFree86/Linux-x86_64/$NGX_DRIVER/NVIDIA-Linux-x86_64-$NGX_DRIVER.run" \
      && sha_ok "$run" "$NGX_RUN_SHA256" \
      && sh "$run" -x --target /tmp/nv-x >/dev/null 2>&1 \
      && cp "/tmp/nv-x/libnvidia-ngx.so.$NGX_DRIVER" "$lib"
    rm -rf "$run" /tmp/nv-x
  fi
  if [ -s "$lib" ]; then
    ln -sf "$lib" "$NGX_LIB" && ldconfig \
      && echo "video: rtx — NGX драйвера нет, запасная $NGX_DRIVER за $(( $(date +%s) - t0 )) с"
  else
    echo "video: rtx — NGX драйвера нет и запасную взять не удалось: RTX Video ответит ошибкой"
  fi
}

if [ -d /comfyui/custom_nodes/Nvidia_RTX_Nodes_ComfyUI ]; then
  rtx_vfx && rtx_ngx \
    && { timeout 180 "$PY" /nastia/rtx_warmup.py & }
fi

# ── Внимание ComfyUI (по умолчанию — как было: pytorch) ──────────────────────
# NASTIA_SAGE_ATTENTION=1 — SageAttention 2 (в образе с ветки bench-sage2) глобально, флаг
# ComfyUI --use-sage-attention. Узел ModelAttentionBackend=pytorch в графе возвращает
# конкретной модели pytorch. Пакета нет / не импортируется — воркер НЕ стартует (явная
# ошибка вместо тихого возврата на pytorch: замер иначе врёт).
# NASTIA_COMFY_EXTRA_ARGS — прочие флаги main.py (для замеров), по умолчанию пусто.
NASTIA_COMFY_ARGS="${NASTIA_COMFY_EXTRA_ARGS:-}"
case "${NASTIA_SAGE_ATTENTION:-0}" in
  1|true|TRUE|yes)
    if "$PY" -c "import sageattention" 2>/dev/null; then
      NASTIA_COMFY_ARGS="$NASTIA_COMFY_ARGS --use-sage-attention"
      echo "video: внимание — SageAttention $("$PY" -c "import importlib.metadata as m; print(m.version('sageattention'))")"
    else
      echo "video: NASTIA_SAGE_ATTENTION=1, но sageattention не импортируется — образ без sage"
      "$PY" -c "import sageattention" 2>&1 | tail -5
      exit 1
    fi ;;
  *) echo "video: внимание — pytorch (NASTIA_SAGE_ATTENTION не задан)" ;;
esac
[ -n "$NASTIA_COMFY_ARGS" ] && echo "video: доп. флаги ComfyUI:$NASTIA_COMFY_ARGS"
export NASTIA_COMFY_ARGS
exec /start.sh
