# FastFilmGrain — без изменений из comfyui-vrgamedevgirl (Jean Thompson), коммит
# b442afd031326ab5b79378e18b656e1ec024a975, nodes.py; лицензия на этом коммите — MIT
# (см. NOTICE). Изменён только импорт: модуль ComfyUI вместо `import comfy`.

import comfy.model_management
import torch


class FastFilmGrain:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "images": ("IMAGE",),
                "grain_intensity": (
                    "FLOAT", {"default": 0.04, "min": 0.001, "max": 1.0, "step": 0.001}
                ),
                "saturation_mix": (
                    "FLOAT", {"default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01}
                ),
                "batch_size": (
                    "INT", {"default": 4, "min": 0, "max": 500, "step": 1}
                ),
            }
        }

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "apply_grain"
    CATEGORY = "video/enhancement"
    DESCRIPTION = "Adds lightweight film grain"

    def apply_grain(self, images, grain_intensity, saturation_mix, batch_size):
        device = comfy.model_management.get_torch_device()

        # batch_size==0 (allowed by INPUT_TYPES min) would crash range();
        # treat as "process everything in a single batch".
        step = batch_size if batch_size > 0 else images.shape[0]

        outputs = []
        for i in range(0, images.shape[0], step):
            batch = images[i:i + step].to(device)
            grain = torch.randn_like(batch)

            grain[:, :, :, 0] *= 2.0  # red
            grain[:, :, :, 2] *= 3.0  # blue

            gray = grain[:, :, :, 1].unsqueeze(3).repeat(1, 1, 1, 3)
            grain = saturation_mix * grain + (1.0 - saturation_mix) * gray

            output = batch + grain * grain_intensity
            output = output.clamp(0.0, 1.0)
            outputs.append(output.cpu())
            del batch, grain, gray, output

        output = torch.cat(outputs, dim=0)
        output = output.to(comfy.model_management.intermediate_device())
        return (output,)
