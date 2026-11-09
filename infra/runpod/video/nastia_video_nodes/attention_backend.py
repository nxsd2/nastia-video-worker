"""NastiaAttentionBackend — выбор внимания для ОДНОЙ модели, включая SageAttention.

Узел ядра ModelAttentionBackend (ComfyUI v0.43) знает только «pytorch attention» и
«comfy kitchen attention», а sage ядро включает лишь глобально (--use-sage-attention).
Этот узел делает то же, что ModelAttentionBackend (model.clone() +
set_model_optimized_attention), но берёт любую функцию из реестра ядра
(comfy.ldm.modules.attention.REGISTERED_ATTENTION_FUNCTIONS): `sage` регистрируется,
когда пакет sageattention импортируется. Так в одном графе можно поставить sage только
на low-проход (или на оба) без перезапуска ComfyUI и без глобального флага.

Нет запрошенной функции — узел ПАДАЕТ (а не тихо возвращает pytorch): замер иначе врёт.
Ошибку самого ядра sage во время сэмплинга ядро ComfyUI гасит возвратом на pytorch с
записью «Error running sage attention» в журнал — при замере журнал проверять.
"""

import comfy.ldm.modules.attention as comfy_attention

_LABELS = {
    "pytorch attention": "pytorch",
    "comfy kitchen attention": "comfy_kitchen_int8",
    "sage attention": "sage",
}


class NastiaAttentionBackend:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "model": ("MODEL",),
                "attention": (list(_LABELS), {"default": "sage attention"}),
            }
        }

    RETURN_TYPES = ("MODEL",)
    FUNCTION = "patch"
    CATEGORY = "model/patch"

    def patch(self, model, attention):
        name = _LABELS[attention]
        func = attention_module_function(name)
        m = model.clone()
        m.set_model_optimized_attention(func)
        return (m,)


def attention_module_function(name):
    func = comfy_attention.get_attention_function(name, None)
    if func is None:
        raise RuntimeError(
            f"NastiaAttentionBackend: функция внимания '{name}' недоступна в этом образе "
            f"(есть: {', '.join(sorted(comfy_attention.REGISTERED_ATTENTION_FUNCTIONS))})"
        )
    return func
