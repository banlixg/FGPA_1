"""Create a NEW ordinary folder with four verified 24-bit BMPs and PCM WAV.
Never formats a drive, edits existing media, or opens a physical device.
"""
import argparse,hashlib,json,math,struct,wave
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=False)
    font_path=Path('C:/Windows/Fonts/consola.ttf')
    font=ImageFont.truetype(str(font_path),38) if font_path.exists() else ImageFont.load_default(size=38)
    small=ImageFont.truetype(str(font_path),22) if font_path.exists() else ImageFont.load_default(size=22)
    colors=[(215,43,48),(27,145,78),(37,97,206),(147,56,195)];thumbs=[];info=[]
    for i,color in enumerate(colors,1):
        im=Image.new('RGB',(640,480),color);d=ImageDraw.Draw(im)
        d.rectangle((12,12,627,467),outline='white',width=4)
        d.text((32,28),f'TEAM FRAME {i:02d}',fill='white',font=font)
        d.text((32,90),'TOP LEFT / RGB888 / 640 x 480',fill='white',font=small)
        d.polygon([(320,130),(280,190),(304,190),(304,250),(336,250),(336,190),(360,190)],fill='white')
        for col,c in enumerate([(255,0,0),(0,255,0),(0,0,255),(255,255,0),(0,255,255),(255,0,255),(255,255,255),(0,0,0)]):
            d.rectangle((32+col*72,280,103+col*72,365),fill=c)
        d.text((32,403),'BOTTOM / KEY2 NEXT / KEY4 AUTO',fill='white',font=small)
        f=a.output/f'IMG{i:04d}.BMP';im.save(f,format='BMP');raw=f.read_bytes()
        assert len(raw)==921654 and raw[:2]==b'BM'
        assert struct.unpack_from('<IiiHHI',raw,14)==(40,640,480,1,24,0)
        assert struct.unpack_from('<I',raw,10)[0]==54
        with Image.open(f) as check:assert check.convert('RGB').tobytes()==im.tobytes()
        thumbs.append(im.resize((320,240)));info.append(dict(file=f.name,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()))
    frequencies=[261.6256,329.6276,391.9954,523.2511,391.9954,329.6276,293.6648,261.6256]
    pcm=bytearray();rate=48000;note_frames=24000
    for frequency in frequencies:
        for j in range(note_frames):
            envelope=min(1.0,j/480,(note_frames-1-j)/480)
            sample=round(6000*envelope*math.sin(2*math.pi*frequency*j/rate));pcm+=struct.pack('<hh',sample,sample)
    f=a.output/'AUDIO.WAV'
    with wave.open(str(f),'wb') as out:out.setnchannels(2);out.setsampwidth(2);out.setframerate(rate);out.writeframes(pcm)
    with wave.open(str(f),'rb') as check:assert check.getnchannels()==2 and check.getframerate()==48000 and check.getsampwidth()==2 and check.readframes(192000)==pcm
    raw=f.read_bytes();info.append(dict(file=f.name,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),format='PCM1 stereo signed16 48000 Hz',seconds=4))
    sheet=Image.new('RGB',(640,480))
    for i,im in enumerate(thumbs):sheet.paste(im,((i%2)*320,(i//2)*240))
    sheet.save(a.output/'预期四图.png')
    (a.output/'MEDIA_MANIFEST.json').write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf8')
    print('Created',a.output,'BMP=4 WAV=1 (no card access)')
if __name__=='__main__':main()
