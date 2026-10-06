import wave
import sys

def s24_to_hex(v):
    if v < 0:
        v = (1 << 24) + v
    return f"{v & 0xFFFFFF:06X}"

def read_s24le(data3):
    v = int.from_bytes(data3, byteorder="little", signed=False)
    if v & 0x800000:
        v -= 1 << 24
    return v

def wav_to_mif(wav_path, mif_path):
    with wave.open(wav_path, "rb") as wf:
        nch = wf.getnchannels()
        sw  = wf.getsampwidth()
        sr  = wf.getframerate()
        nfr = wf.getnframes()

        if sr != 48000:
            raise ValueError(f"采样率必须是 48000，当前是 {sr}")
        if nch not in (1, 2):
            raise ValueError(f"只支持 1 或 2 声道，当前是 {nch}")
        if sw not in (2, 3):
            raise ValueError(f"只支持 16bit 或 24bit PCM，当前字节宽度是 {sw}")

        raw = wf.readframes(nfr)

    samples = []
    frame_size = nch * sw

    for i in range(nfr):
        base = i * frame_size

        if sw == 2:
            if nch == 1:
                l16 = int.from_bytes(raw[base:base+2], "little", signed=True)
                r16 = l16
            else:
                l16 = int.from_bytes(raw[base:base+2], "little", signed=True)
                r16 = int.from_bytes(raw[base+2:base+4], "little", signed=True)

            # 16bit 扩展到 24bit
            l24 = l16 << 8
            r24 = r16 << 8

        else:  # sw == 3
            if nch == 1:
                l24 = read_s24le(raw[base:base+3])
                r24 = l24
            else:
                l24 = read_s24le(raw[base:base+3])
                r24 = read_s24le(raw[base+3:base+6])

        samples.append((l24, r24))

    depth = len(samples)

    with open(mif_path, "w", encoding="utf-8") as f:
        f.write(f"WIDTH=48;\n")
        f.write(f"DEPTH={depth};\n\n")
        f.write("ADDRESS_RADIX=UNS;\n")
        f.write("DATA_RADIX=HEX;\n\n")
        f.write("CONTENT BEGIN\n")
        for addr, (l24, r24) in enumerate(samples):
            f.write(f"{addr} : {s24_to_hex(l24)}{s24_to_hex(r24)};\n")
        f.write("END;\n")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法: python wav_to_mif.py input.wav output.mif")
        sys.exit(1)

    wav_to_mif(sys.argv[1], sys.argv[2])
    print("转换完成")