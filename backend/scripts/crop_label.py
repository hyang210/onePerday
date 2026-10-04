import json
import os
import sys
from pathlib import Path

from PIL import Image, ImageOps
from ultralytics import YOLO


def clamp(value, min_value, max_value):
    return max(min_value, min(value, max_value))


def main():
    if len(sys.argv) != 4:
        print(
            json.dumps(
                {
                    "success": False,
                    "error": "Usage: crop_label.py <model_path> <input_path> <output_dir>",
                },
                ensure_ascii=False,
            )
        )
        sys.exit(2)

    model_path = Path(sys.argv[1])
    input_path = Path(sys.argv[2])
    output_dir = Path(sys.argv[3])
    output_dir.mkdir(parents=True, exist_ok=True)

    confidence_threshold = float(os.environ.get("YOLO_CONF", "0.35"))
    padding_ratio = float(os.environ.get("YOLO_CROP_PADDING", "0.06"))

    # 휴대폰 사진은 회전 정보(EXIF)만 붙어 있는 경우가 많아, 먼저 실제 방향으로 돌려놓습니다.
    # YOLO 검출과 crop이 같은 이미지를 쓰도록 이 이미지를 그대로 YOLO에 넘깁니다.
    image = ImageOps.exif_transpose(Image.open(input_path)).convert("RGB")
    width, height = image.size

    model = YOLO(str(model_path))
    results = model.predict(
        source=image,
        conf=confidence_threshold,
        save=False,
        verbose=False,
    )

    if not results or results[0].boxes is None or len(results[0].boxes) == 0:
        print(
            json.dumps(
                {
                    "success": False,
                    "error": "No supplement_label detected.",
                },
                ensure_ascii=False,
            )
        )
        return

    boxes = results[0].boxes
    confidences = boxes.conf.cpu().numpy()
    best_index = int(confidences.argmax())
    confidence = float(confidences[best_index])
    xyxy = boxes.xyxy[best_index].cpu().numpy().tolist()

    x1, y1, x2, y2 = xyxy
    pad_x = (x2 - x1) * padding_ratio
    pad_y = (y2 - y1) * padding_ratio

    crop_box = (
        int(clamp(x1 - pad_x, 0, width)),
        int(clamp(y1 - pad_y, 0, height)),
        int(clamp(x2 + pad_x, 0, width)),
        int(clamp(y2 + pad_y, 0, height)),
    )

    crop = image.crop(crop_box)
    crop_path = output_dir / "label_crop.jpg"
    crop.save(crop_path, "JPEG", quality=95)

    print(
        json.dumps(
            {
                "success": True,
                "cropPath": str(crop_path),
                "confidence": confidence,
                "box": [float(v) for v in crop_box],
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(
            json.dumps(
                {
                    "success": False,
                    "error": str(exc),
                },
                ensure_ascii=False,
            )
        )
        sys.exit(1)
