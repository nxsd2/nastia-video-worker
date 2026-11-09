# Образ видео-воркера (полигон видео: Wan 2.2 i2v, MiniMax H3, GBRX Wan 2.2 I2V V13).
#
# Сборка — GitHub Actions `.github/workflows/video-worker-image.yml` →
# ghcr.io/nexsidee/nastia-video-worker:<sha>. Контекст сборки — `infra/runpod/video/`.
#
# ❗️Образ ПУБЛИЧНЫЙ: в нём только открытый код (ComfyUI, пакеты узлов, наш старт-скрипт)
# и веса RIFE (MIT, 21 МБ). Ни секретов, ни моделей владельца, ни LoRA. Проприетарное
# NVIDIA (nvidia-vfx — лицензия NVIDIA Software License Agreement: прав на распространение
# нет; libnvidia-ngx из драйвера) в образ НЕ кладётся — `worker_start.sh` ставит их на
# старте воркера (из кэша моделей `runtime/`, иначе с pypi.nvidia.com / download.nvidia.com,
# со сверкой sha256).
#
# Отличия от стокового runpod/worker-comfyui:5.10.0-base-cuda12.8.1 (ComfyUI 0.34.0):
# * ComfyUI — тег v0.43.0 (узлы Wan 2.2 и MiniMax H3; раньше поднимался на старте);
# * пакеты узлов по закреплённым коммитам (ворклоу GBRX):
#   - gguf (calcuis, cnr_id `gguf`) — LoaderGGUF;
#   - ComfyUI_essentials (cubiq) — SimpleMath+;
#   - ComfyUI-VideoHelperSuite — VHS_SelectEveryNthImage;
#   - Nvidia_RTX_Nodes_ComfyUI (Comfy-Org, v0.2.1) — RTXVideoSuperResolution;
#   - nastia_video_nodes (наш): FL_RIFE и FL_IntToFloat — файлы из ComfyUI_Fill-Nodes
#     (Apache-2.0; весь пакет не ставим: ~30 тяжёлых зависимостей и свои HTTP-маршруты),
#     FastFilmGrain — из comfyui-vrgamedevgirl на коммите под MIT (у новых версий пакета
#     лицензия запрещает коммерческий сервис генерации, а узла там уже нет);
# * Power Lora Loader (rgthree) и CR Simple Text Watermark не ставятся: конвертер полигона
#   раскладывает Power Lora в цепочку LoraLoader ядра, знак выбрасывает (решение владельца);
# * обработчик — наш поверх стокового (nastia_handler.py): ролик любой длины — в наше ведро
#   по подписанным ссылкам из задачи (RunPod не отдаёт ответ больше ~20 МБ);
# * SageAttention 2.2.0 (thu-ml, Apache-2.0) — собирается в отдельной ступени `sage-build`
#   (nvcc 12.8 + тот же torch, что в образе) под sm_89 (4090/L40S) и sm_120 (5090/PRO 6000),
#   в итоговый образ — только wheel. ВЫКЛЮЧЕН по умолчанию: включает переменная пода
#   NASTIA_SAGE_ATTENTION=1 (worker_start.sh → флаг ComfyUI --use-sage-attention). Узла
#   выбора sage в ComfyUI v0.43 нет (ModelAttentionBackend знает только pytorch и comfy
#   kitchen), только глобальный флаг; узел ModelAttentionBackend=pytorch в графе
#   возвращает модели pytorch и при включённом флаге.
ARG BASE_IMAGE=runpod/worker-comfyui:5.10.0-base-cuda12.8.1@sha256:45a1abd8796dbbcbc631f3d7d0db942946ce2f82ff24a070e3e6c527eeff9c47
FROM ${BASE_IMAGE} AS app

ARG COMFYUI_REF=v0.43.0
ARG GGUF_SHA=98e433ad74cf96aa3aa8539a9c27f8f99cadd4cd
ARG ESSENTIALS_SHA=9d9f4bedfc9f0321c19faf71855e228c93bd0dc9
ARG VHS_SHA=4d907bee61e92c2e65af3bd6383a4e4d356126d1
ARG RTX_NODES_SHA=38d790ded00650681fa3645362efe28c8560cf40
ARG FILL_NODES_SHA=a32f9b6a5a55528731d9e6c38a2fd2ce89cb2819
# Веса RIFE — с ревизией и sha256 (FL_RIFE иначе качает их при первом запуске).
ARG RIFE_REPO=https://huggingface.co/MachineDelusions/RIFE/resolve/15e1387eeef9858f5267cf011134aef9192469f0
ARG RIFE47_SHA256=6a8a825ab2750558bdd20dcced386fd82b7222c7ba58c11d3b611d9c44f1be63
ARG RIFE49_SHA256=e55fd00f3cc184e3c65961f4bb827a9da022e78eed36b055242c0ac30000d533

# NGX (RTX Video) монтируется в контейнер только с правом `ngx`; `all` его включает.
ENV NVIDIA_DRIVER_CAPABILITIES=all
ENV NASTIA_COMFYUI_BAKED_REF=${COMFYUI_REF}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ComfyUI → тег. Пины transformers/huggingface-hub — как у стокового образа (5.x/1.x
# ломают старт ComfyUI); torch cu128 уже стоит и требованием `torch` не меняется.
RUN cd /comfyui \
    && git fetch -q --depth 1 origin "refs/tags/${COMFYUI_REF}:refs/tags/${COMFYUI_REF}" \
    && git -c advice.detachedHead=false checkout -q "${COMFYUI_REF}" \
    && uv pip install --python /opt/venv/bin/python -r requirements.txt \
         "transformers>=4.50.3,<5" "huggingface-hub<1.0" \
    && rm -rf /root/.cache/uv

# Пакеты узлов по коммитам.
RUN set -eux; \
    fetch() { git init -q "$1"; git -C "$1" remote add origin "$2"; \
              git -C "$1" fetch -q --depth 1 origin "$3"; git -C "$1" -c advice.detachedHead=false checkout -q FETCH_HEAD; \
              rm -rf "$1/.git"; }; \
    cd /comfyui/custom_nodes; \
    fetch gguf https://github.com/calcuis/gguf "${GGUF_SHA}"; \
    fetch ComfyUI_essentials https://github.com/cubiq/ComfyUI_essentials "${ESSENTIALS_SHA}"; \
    fetch ComfyUI-VideoHelperSuite https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite "${VHS_SHA}"; \
    fetch Nvidia_RTX_Nodes_ComfyUI https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI "${RTX_NODES_SHA}"; \
    fetch /tmp/fill https://github.com/filliptm/ComfyUI_Fill-Nodes "${FILL_NODES_SHA}"; \
    dst=/comfyui/custom_nodes/nastia_video_nodes/fill; \
    mkdir -p "$dst/nodes/video" "$dst/nodes/utility" "$dst/nodes/cache/rife_models"; \
    cp /tmp/fill/LICENSE "$dst/LICENSE"; \
    cp /tmp/fill/nodes/__init__.py /tmp/fill/nodes/rife_arch.py "$dst/nodes/"; \
    cp /tmp/fill/nodes/video/__init__.py /tmp/fill/nodes/video/FL_RIFE.py "$dst/nodes/video/"; \
    cp /tmp/fill/nodes/utility/__init__.py /tmp/fill/nodes/utility/FL_NumberConverter.py "$dst/nodes/utility/"; \
    : > "$dst/__init__.py"; \
    rm -rf /tmp/fill; \
    for name in rife47 rife49; do \
      wget -q -O "$dst/nodes/cache/rife_models/$name.pth" "${RIFE_REPO}/$name.pth"; \
    done; \
    echo "${RIFE47_SHA256}  $dst/nodes/cache/rife_models/rife47.pth" | sha256sum -c -; \
    echo "${RIFE49_SHA256}  $dst/nodes/cache/rife_models/rife49.pth" | sha256sum -c -

# Зависимости пакетов: VHS — opencv + imageio-ffmpeg; essentials — numba (импорт при
# загрузке), kornia/scipy уже у ComfyUI; rembg/transparent-background essentials
# грузит лениво — не ставим. gguf и узлы RTX — без своих (nvidia-vfx — на старте).
RUN uv pip install --python /opt/venv/bin/python \
      -r /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt numba \
    && rm -rf /root/.cache/uv

COPY nastia_video_nodes/ /comfyui/custom_nodes/nastia_video_nodes/
COPY worker_start.sh rtx_warmup.py build_check.sh /nastia/

# Обработчик (9 ноя): стоковый handler.py → модуль comfy_stock_handler, на его место —
# наш (nastia_handler.py): ролик кладётся в наше ведро по подписанным ссылкам из задачи,
# ключей от ведра на воркере нет. /start.sh по-прежнему запускает /handler.py.
COPY nastia_handler.py /nastia/
RUN mv /handler.py /comfy_stock_handler.py && cp /nastia/nastia_handler.py /handler.py

# Доп. аргументы ComfyUI: стоковый /start.sh запускает main.py с жёстким набором флагов —
# вставляем в обе строки запуска `${NASTIA_COMFY_ARGS:-}` (заполняет worker_start.sh;
# пусто — запуск как раньше). Не нашлось ровно двух строк — сборка падает.
RUN sed -i 's#--log-stdout &$#--log-stdout ${NASTIA_COMFY_ARGS:-} \&#' /start.sh \
    && [ "$(grep -c -- '--log-stdout ${NASTIA_COMFY_ARGS:-} &$' /start.sh)" = 2 ] \
    || { echo "start.sh: строки запуска ComfyUI не найдены"; grep -n main.py /start.sh; exit 1; }

# ── SageAttention 2 (сборка wheel) ───────────────────────────────────────────
# От `app`: тот же python 3.12, venv и torch (cu128) — ABI расширений совпадает. nvcc и
# заголовки CUDA 12.8 — из apt-репозитория NVIDIA, он уже подключён в базовом образе.
# Ступень в итоговый образ не попадает (только wheel).
FROM app AS sage-build
ARG SAGE_REF=v2.2.0
ARG SAGE_SHA=eb615cf6cf4d221338033340ee2de1c37fbdba4a
ARG SAGE_ARCHS="8.9;12.0"
ARG SAGE_MAX_JOBS=2
RUN apt-get update && apt-get install -y --no-install-recommends \
      g++ python3.12-dev \
      cuda-nvcc-12-8 cuda-cudart-dev-12-8 cuda-nvrtc-dev-12-8 cuda-nvtx-12-8 \
      cuda-profiler-api-12-8 cuda-cuobjdump-12-8 \
      libcublas-dev-12-8 libcusparse-dev-12-8 libcusolver-dev-12-8 libcurand-dev-12-8 \
    && rm -rf /var/lib/apt/lists/*
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=/usr/local/cuda/bin:${PATH}
RUN set -eux; \
    /usr/local/cuda/bin/nvcc --version | tail -2; \
    python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'cxx11abi', torch._C._GLIBCXX_USE_CXX11_ABI)"; \
    uv pip install --python /opt/venv/bin/python ninja setuptools wheel packaging; \
    git init -q /tmp/sage; git -C /tmp/sage remote add origin https://github.com/thu-ml/SageAttention; \
    git -C /tmp/sage fetch -q --depth 1 origin "refs/tags/${SAGE_REF}"; \
    [ "$(git -C /tmp/sage rev-parse FETCH_HEAD)" = "${SAGE_SHA}" ]; \
    git -C /tmp/sage -c advice.detachedHead=false checkout -q FETCH_HEAD; \
    cd /tmp/sage; \
    TORCH_CUDA_ARCH_LIST="${SAGE_ARCHS}" MAX_JOBS="${SAGE_MAX_JOBS}" EXT_PARALLEL=1 \
      python -m pip wheel -v --no-build-isolation --no-deps -w /wheels . >/tmp/sage-build.log 2>&1 \
      || { grep -iE "error|killed|fatal" /tmp/sage-build.log | head -60; tail -80 /tmp/sage-build.log; exit 1; }; \
    grep -E "Target compute capabilities|^creating|Successfully built" /tmp/sage-build.log | head -20; \
    ls -la /wheels; \
    mkdir /tmp/x; cd /tmp/x; python -m zipfile -e /wheels/sageattention-*.whl .; \
    for so in sageattention/_qattn_sm80*.so sageattention/_qattn_sm89*.so sageattention/_fused*.so; do \
      elfs=$(cuobjdump --list-elf "$so"); echo "$so: $(echo "$elfs" | grep -oE 'sm_[0-9]+' | sort -u | tr '\n' ' ')"; \
      { echo "$elfs" | grep -q sm_89 && echo "$elfs" | grep -q sm_120; } || { echo "$so: нет sm_89/sm_120"; exit 1; }; \
    done; \
    rm -rf /tmp/x /tmp/sage /tmp/sage-build.log

# ── Итоговый образ ───────────────────────────────────────────────────────────
FROM app
# SageAttention: wheel из `sage-build`. gcc + python3.12-dev — для triton: на sm_89 sage
# квантует Q/K ядром triton, а triton на первом запуске компилирует свой загрузчик C
# (без компилятора sage падал на поде 8 ноя). На sm_120 путь целиком на CUDA.
COPY --from=sage-build /wheels/ /tmp/wheels/
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev python3.12-dev \
    && rm -rf /var/lib/apt/lists/* \
    && uv pip install --no-deps --python /opt/venv/bin/python /tmp/wheels/sageattention-*.whl \
    && rm -rf /tmp/wheels /root/.cache/uv

# Проверка сборки: ComfyUI стартует на CPU и грузит все пакеты узлов; не загрузился
# нужный пакет — сборка падает (узлы RTX без nvidia-vfx на сборке не грузятся — норма).
# SKIP_BUILD_CHECK=1 — только для сборки под эмуляцией (Mac: torch на qemu/Rosetta
# падает «Illegal instruction»); в GitHub Actions проверка идёт всегда.
ARG SKIP_BUILD_CHECK=0
RUN if [ "${SKIP_BUILD_CHECK}" = "1" ]; then echo "build_check пропущен (эмуляция)"; else bash /nastia/build_check.sh; fi

CMD ["bash", "/nastia/worker_start.sh"]
