"""Generate four test BMPs using Python's standard library; no Pillow required.

Only writes to the chosen output folder. Never accesses a TF device.
Standard positive-height BMPs. Board orientation must be tested separately.
"""
import argparse
import struct
from pathlib import Path

FONT = {
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    " ": ["00000"] * 7,
}


def create_image(number):
    width, height = 640, 480
    background = [(24, 32, 56), (32, 52, 32), (56, 32, 24), (40, 24, 56)][number - 1]
    rows = [bytearray(bytes(background) * width) for _ in range(height)]

    def rect(x0, y0, x1, y1, rgb):
        for y in range(max(0, y0), min(height, y1)):
            rows[y][max(0, x0) * 3:min(width, x1) * 3] = bytes(rgb) * (min(width, x1) - max(0, x0))

    def text(label, x, y, scale=4, rgb=(255, 255, 255)):
        for char in label:
            for gy, line in enumerate(FONT[char]):
                for gx, bit in enumerate(line):
                    if bit == "1":
                        rect(x + gx * scale, y + gy * scale,
                             x + (gx + 1) * scale, y + (gy + 1) * scale, rgb)
            x += 6 * scale

    rect(0, 0, width, 3, (255, 255, 255))
    rect(0, height - 3, width, height, (255, 255, 255))
    rect(0, 0, 3, height, (255, 255, 255))
    rect(width - 3, 0, width, height, (255, 255, 255))
    rect(12, 12, 88, 88, (255, 0, 0))
    rect(552, 12, 628, 88, (0, 255, 0))
    rect(12, 392, 88, 468, (0, 0, 255))
    rect(552, 392, 628, 468, (255, 255, 0))
    text("TL", 28, 37, 4)
    text("TR", 568, 37, 4, (0, 0, 0))
    text("BL", 28, 419, 4)
    text("BR", 568, 419, 4, (0, 0, 0))
    text("TOP", 276, 28, 5)
    text("BOTTOM", 231, 416, 5)
    text(f"{number:02d}", 215, 148, 18)
    text("TF BMP", 249, 319, 4)
    # Three reference patches help identify channel swaps.
    rect(191, 360, 271, 385, (255, 0, 0))
    rect(281, 360, 361, 385, (0, 255, 0))
    rect(371, 360, 451, 385, (0, 0, 255))
    return rows


def write_bmp(path, rows):
    width, height = 640, 480
    pixel_bytes = width * height * 3
    header = struct.pack("<2sIHHI", b"BM", 54 + pixel_bytes, 0, 0, 54)
    header += struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, pixel_bytes, 2835, 2835, 0, 0)
    with path.open("wb") as stream:
        stream.write(header)
        # BMP stores rows bottom-up and channels BGR.
        for row in reversed(rows):
            bgr = bytearray(len(row))
            bgr[0::3], bgr[1::3], bgr[2::3] = row[2::3], row[1::3], row[0::3]
            stream.write(bgr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "numbered"))
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()
    output = Path(args.out)
    files = [output / f"{number:02d}.bmp" for number in range(1, 5)]
    existing = [path for path in files if path.exists()]
    if existing and not args.overwrite:
        parser.error("Existing BMPs found; select a new folder or use --overwrite explicitly")
    output.mkdir(parents=True, exist_ok=True)
    for number, path in enumerate(files, 1):
        write_bmp(path, create_image(number))
        print(f"GENERATED {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
