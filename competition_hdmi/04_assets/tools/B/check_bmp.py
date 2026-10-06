"""Read-only checker for this project's 640x480, positive-height, 24-bit BMP.

File contents are never changed. Success means offline format compatibility;
it does not verify TF sectors, file continuity, board orientation or HDMI.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path


def inspect_bmp(path):
    path = Path(path)
    result = {"file": str(path.resolve()), "status": "FAIL", "errors": []}
    try:
        data = path.read_bytes()
    except OSError as exc:
        result["errors"].append(str(exc))
        return result
    result["actual_bytes"] = len(data)
    result["sha256"] = hashlib.sha256(data).hexdigest()
    if len(data) < 54:
        result["errors"].append("File shorter than the 54-byte BMP header")
        return result
    fields = {
        "signature": data[:2].decode("ascii", errors="replace"),
        "declared_bytes": struct.unpack_from("<I", data, 2)[0],
        "pixel_offset": struct.unpack_from("<I", data, 10)[0],
        "dib_bytes": struct.unpack_from("<I", data, 14)[0],
        "width": struct.unpack_from("<i", data, 18)[0],
        "height": struct.unpack_from("<i", data, 22)[0],
        "planes": struct.unpack_from("<H", data, 26)[0],
        "bpp": struct.unpack_from("<H", data, 28)[0],
        "compression": struct.unpack_from("<I", data, 30)[0],
        "image_bytes": struct.unpack_from("<I", data, 34)[0],
    }
    result.update(fields)
    errors = result["errors"]
    requirements = [
        (data[:2] == b"BM", "Signature must be BM; renaming JPG is not conversion"),
        (fields["dib_bytes"] in (40, 52, 56, 108, 124), "Unsupported DIB header"),
        (fields["width"] == 640, "Width must be 640"),
        (fields["height"] == 480, "Height must be +480; top-down BMP is not supported here"),
        (fields["planes"] == 1, "Planes must be 1"),
        (fields["bpp"] == 24, "Bit depth must be 24"),
        (fields["compression"] == 0, "Compression must be 0 (BI_RGB)"),
        (fields["pixel_offset"] >= 14 + fields["dib_bytes"], "Pixel offset overlaps header"),
        (fields["declared_bytes"] == len(data), "Declared file size differs from actual size"),
    ]
    for passed, message in requirements:
        if not passed:
            errors.append(message)
    stride = ((640 * 24 + 31) // 32) * 4
    expected_pixels = stride * 480
    result["expected_stride"] = stride
    result["expected_pixel_bytes"] = expected_pixels
    if fields["pixel_offset"] + expected_pixels != len(data):
        errors.append("Pixel data must occupy exactly 921600 bytes; truncated/trailing data rejected")
    if fields["image_bytes"] not in (0, expected_pixels):
        errors.append("Image-size field must be 0 or 921600")
    if not errors:
        result["status"] = "OFFLINE_PASS"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", help="BMP file(s) or folder(s)")
    parser.add_argument("--json", dest="json_path", help="Optional explicit report output path")
    args = parser.parse_args()
    files = []
    for value in args.paths:
        path = Path(value)
        if path.is_dir():
            found = sorted(p for p in path.iterdir() if p.is_file() and p.suffix.lower() == ".bmp")
            if not found:
                print(f"FAIL: no BMP files in {path}")
                return 1
            files.extend(found)
        else:
            files.append(path)
    results = [inspect_bmp(path) for path in files]
    for item in results:
        print(f"{item['status']} {item['file']}")
        if "width" in item:
            print(f"  {item['width']}x{item['height']} bpp={item['bpp']} compression={item['compression']} "
                  f"offset={item['pixel_offset']} bytes={item['actual_bytes']}")
        for error in item["errors"]:
            print(f"  ERROR: {error}")
    if args.json_path:
        output = Path(args.json_path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    passed = all(item["status"] == "OFFLINE_PASS" for item in results)
    print(f"SUMMARY: {len(results)} file(s), {'OFFLINE_PASS' if passed else 'FAIL'}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
