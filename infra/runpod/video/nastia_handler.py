"""Обработчик видео-воркера (9 ноя): стоковый worker-comfyui 5.10.0 + ролик в наше
ведро по подписанным ссылкам.

Зачем. RunPod не отдаёт результат работы больше ~20 МБ, а стоковый обработчик без
`BUCKET_ENDPOINT_URL` кладёт ролик base64 прямо в ответ — ролик ~8 с и длиннее до
бэкенда не доходил. Стоковая выгрузка в S3 (`rp_upload`) требует ключи от ведра на
воркере — а в нашем ведре данные людей. Поэтому ключей на воркере нет: бэкенд кладёт
в задачу `input.nastia_upload.targets` — подписанные ссылки на ЗАПИСЬ (PUT) отдельных
ключей `playground-video/u-<метка>-<n>.<ext>` с типом в подписи; каждая пишет ровно
свой файл и живёт чуть дольше жизни работы.

Как. Стоковый `handler.py` переименован в образе в `comfy_stock_handler.py` и
импортируется как модуль; его файлы проходят через `rp_upload.upload_image(job_id,
путь)`, когда задан `BUCKET_ENDPOINT_URL`. На время задачи со ссылками мы ставим
этот флаг и подменяем `rp_upload` своим загрузчиком:
* файл видео со свободной ссылкой своего типа → PUT по ссылке; в ответе
  `{"type": "s3_key", "data": <ключ>}` (ссылки в ответ не идут);
* ссылки нет (кадр PNG, тип без слота) → как раньше, base64 в ответе;
* PUT не удался после повторов → ошибка файла в `errors` (стоковое поведение).
Задача без ссылок (старый бэкенд, фото) — стоковый путь без изменений.

Воркер берёт одну задачу за раз (concurrency 1 у serverless по умолчанию), поэтому
состояние задачи — в модуле.

❗️Ссылки и имена файлов — не в журнал (имя файла несёт префикс из ворклоу
владельца): печатаем только тип, размер и номер.
"""

from __future__ import annotations

import base64
import os
import time
from typing import Any

import comfy_stock_handler as stock
import requests

KEY_MARK = "nastia-key:"
B64_MARK = "nastia-b64:"
PUT_ATTEMPTS = 3
PUT_PAUSES = (2.0, 6.0)
PUT_TIMEOUT = (15, 900)  # соединение, чтение ответа (большой ролик на медленной линии)

_targets: list[dict[str, str]] = []


def _clean_targets(raw: Any) -> list[dict[str, str]]:
    if not isinstance(raw, dict):
        return []
    found = []
    for target in raw.get("targets") or []:
        if not isinstance(target, dict):
            continue
        ext, content_type, key, url = (str(target.get(k) or "") for k in ("ext", "content_type", "key", "url"))
        if ext and content_type and key.startswith("playground-video/") and url.startswith("https://"):
            found.append({"ext": ext.lower(), "content_type": content_type, "key": key, "url": url})
    return found


def _take(ext: str) -> dict[str, str] | None:
    for index, target in enumerate(_targets):
        if target["ext"] == ext:
            return _targets.pop(index)
    return None


def _put(path: str, target: dict[str, str]) -> None:
    size = os.path.getsize(path)
    last: Exception | None = None
    for attempt in range(PUT_ATTEMPTS):
        try:
            with open(path, "rb") as body:
                answer = requests.put(
                    target["url"],
                    data=body,
                    headers={"Content-Type": target["content_type"], "Content-Length": str(size)},
                    timeout=PUT_TIMEOUT,
                )
            if answer.status_code in (200, 201, 204):
                print(f"nastia-upload - {target['ext']} {size} Б положен (попытка {attempt + 1})")
                return
            last = RuntimeError(f"хранилище ответило {answer.status_code}")
            if answer.status_code < 500 and answer.status_code != 429:
                break  # 403 (истекла/не та подпись) повтором не лечится
        except requests.RequestException as error:
            last = RuntimeError(f"сеть: {type(error).__name__}")
        if attempt < PUT_ATTEMPTS - 1:
            time.sleep(PUT_PAUSES[min(attempt, len(PUT_PAUSES) - 1)])
    raise RuntimeError(f"ролик {target['ext']} {size} Б не положен в хранилище: {last}")


class _Uploader:
    """Подмена `runpod.serverless.utils.rp_upload` для стокового обработчика."""

    @staticmethod
    def upload_image(job_id: str, path: str) -> str:  # noqa: ARG004 — подпись стокового вызова
        ext = os.path.splitext(path)[1].lstrip(".").lower()
        target = _take(ext)
        if target is None:
            with open(path, "rb") as file:
                return B64_MARK + base64.b64encode(file.read()).decode("ascii")
        _put(path, target)
        return KEY_MARK + target["key"]


def _relabel(result: Any) -> Any:
    if not isinstance(result, dict):
        return result
    for item in result.get("images") or []:
        if not isinstance(item, dict) or not isinstance(item.get("data"), str):
            continue
        data = item["data"]
        if data.startswith(KEY_MARK):
            item["type"], item["data"] = "s3_key", data[len(KEY_MARK) :]
        elif data.startswith(B64_MARK):
            item["type"], item["data"] = "base64", data[len(B64_MARK) :]
    return result


def handler(job: dict) -> Any:
    global _targets
    job_input = job.get("input")
    raw = job_input.pop("nastia_upload", None) if isinstance(job_input, dict) else None
    _targets = _clean_targets(raw)
    if not _targets:
        return stock.handler(job)
    saved_bucket = os.environ.get("BUCKET_ENDPOINT_URL")
    saved_upload = stock.rp_upload
    os.environ["BUCKET_ENDPOINT_URL"] = "nastia-presigned"
    stock.rp_upload = _Uploader
    print(f"nastia-upload - ссылок на запись: {len(_targets)}")
    try:
        return _relabel(stock.handler(job))
    finally:
        stock.rp_upload = saved_upload
        if saved_bucket is None:
            os.environ.pop("BUCKET_ENDPOINT_URL", None)
        else:
            os.environ["BUCKET_ENDPOINT_URL"] = saved_bucket
        _targets = []


if __name__ == "__main__":
    import runpod

    print("nastia-upload - обработчик со ссылками на запись")
    runpod.serverless.start({"handler": handler})
