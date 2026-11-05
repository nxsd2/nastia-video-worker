"""Прогрев RTX Video Super Resolution на старте воркера (фоном, рядом со стартом ComfyUI).

Первая загрузка эффекта NGX — 16–22 с: ядра компилируются в кэш CUDA
(`/root/.nv/ComputeCache`, ~12 МБ). Дальше загрузка 0,25–0,3 с, в том числе в новом
процессе (замер 5 ноя, RTX 5090 и RTX PRO 6000). Кэш привязан к видеокарте, поэтому
в образ его не запечь — греем здесь, чтобы 20 с не платил первый ролик.
Ошибка — одна строка в журнал, воркер работает дальше (узел RTX сам покажет ошибку).
"""

import time

START = time.time()


def main() -> None:
    try:
        import nvvfx
        import torch

        if not torch.cuda.is_available():
            print("video: rtx прогрев — нет CUDA", flush=True)
            return
        frame = torch.rand(3, 480, 832, device="cuda")
        with nvvfx.VideoSuperRes(quality=nvvfx.QualityLevel["ULTRA"], device=0) as effect:
            effect.output_width, effect.output_height = 1040, 600  # ×1,25, как в ворклоу GBRX
            effect.load()
            effect.run(frame)
        torch.cuda.synchronize()
        print(f"video: rtx прогрев за {time.time() - START:.1f} с", flush=True)
    except Exception as error:  # noqa: BLE001 — прогрев не должен валить старт
        print(f"video: rtx прогрев не удался ({type(error).__name__}) за {time.time() - START:.1f} с", flush=True)


if __name__ == "__main__":
    main()
