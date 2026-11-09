"""Узлы ворклоу полигона видео, которых нет в ядре ComfyUI, — без тяжёлых пакетов-источников.

* FL_RIFE, FL_IntToFloat — файлы ComfyUI_Fill-Nodes (filliptm, Apache-2.0, `fill/LICENSE`)
  кладёт в `fill/` Dockerfile на закреплённом коммите; весь пакет не ставится (десятки
  зависимостей — API-сервисы, агенты, PDF — и свои HTTP-маршруты сервера ComfyUI).
  Веса RIFE запечены в `fill/nodes/cache/rife_models/` (FL_RIFE берёт их оттуда).
* FastFilmGrain — `film_grain.py` (comfyui-vrgamedevgirl, коммит под MIT, см. NOTICE).
* NastiaAttentionBackend — наш: внимание для одной модели, включая sage (`attention_backend.py`).

Имена классов — как в исходных пакетах: ворклоу владельца ссылаются на них.
"""

from .attention_backend import NastiaAttentionBackend
from .film_grain import FastFilmGrain
from .fill.nodes.utility.FL_NumberConverter import FL_IntToFloat
from .fill.nodes.video.FL_RIFE import FL_RIFE

NODE_CLASS_MAPPINGS = {
    "FL_RIFE": FL_RIFE,
    "FL_IntToFloat": FL_IntToFloat,
    "FastFilmGrain": FastFilmGrain,
    "NastiaAttentionBackend": NastiaAttentionBackend,
}
NODE_DISPLAY_NAME_MAPPINGS = {
    "FL_RIFE": "FL RIFE Frame Interpolation",
    "FL_IntToFloat": "FL Int to Float",
    "FastFilmGrain": "Fast Film Grain",
    "NastiaAttentionBackend": "Nastia Attention Backend (sage)",
}
__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS"]
