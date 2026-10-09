"""Compose deterministic Godot hand animation with an Aero glass photographic card."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

parser = argparse.ArgumentParser()
parser.add_argument('--frames', type=Path, required=True)
args = parser.parse_args()
output = Path(__file__).resolve().parents[1] / '.github' / 'readme-images'
W, H = 960, 710
INK, MUTED, ACCENT = '#183c48', '#375969', '#79d9ef'

def font(size, bold=False):
    for path in [Path('C:/Windows/Fonts') / ('segoeuib.ttf' if bold else 'segoeui.ttf'), Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')]:
        if path.exists(): return ImageFont.truetype(str(path), size)
    return ImageFont.load_default(size=size)

def arrow(draw, start, end):
    dx, dy = end[0]-start[0], end[1]-start[1]
    length = math.hypot(dx,dy)
    if length < 1: return
    dx,dy=dx/length,dy/length
    draw.line((start,end), fill=ACCENT, width=5)
    for direction in [-1,1]:
        draw.line((end,(end[0]-dx*16+direction*dy*10,end[1]-dy*16-direction*dx*10)),fill=ACCENT,width=5)

photo=ImageOps.fit(Image.open(output/'tutorial-landscape.jpg').convert('RGB'),(W,H))
base=photo.convert('RGBA')
# Frosted light glass retains the photograph's large color shapes behind the hands.
mask=Image.new('L',(W,H)); ImageDraw.Draw(mask).rounded_rectangle((22,20,W-22,H-20),radius=32,fill=255)
glass=Image.blend(photo.filter(ImageFilter.GaussianBlur(20)),Image.new('RGB',(W,H),'#e8f6f9'),0.85)
base.paste(glass,(0,0),mask)
d=ImageDraw.Draw(base); d.rounded_rectangle((22,20,W-22,H-20),radius=32,outline='#f3fdff',width=2)
d.line((49,555,911,555),fill='#c4dfe5',width=1)
gestures={
 'page-turn':('Turn a page','Keep your hand open and sweep from the white bar toward the middle.','A fast inward flick turns the page with a shorter movement.'),
 'finger-scroll':('Scroll a long page','Extend one finger. Slide up or down along the page, then lift away.','Keep the other fingers relaxed; do not clench your hand.'),
 'grab-drag':('Move the book or controls','Clench your hand inside the book or panel and carry it to a new position.','Open your hand to release it.'),
 'pinch-select':('Select a control','Point at the button. Bring your thumb and index finger together.','Release to select again, or tap a nearby button directly.'),
}
for name,(title,line1,line2) in gestures.items():
    metadata=json.loads((args.frames/name/'motion.json').read_text())
    frames=[]
    for index,meta in enumerate(metadata):
        image=base.copy()
        image.alpha_composite(Image.open(args.frames/name/f'{index:03}.png').convert('RGBA'),(30,15))
        draw=ImageDraw.Draw(image)
        point=(meta['point'][0]+30,meta['point'][1]+15)
        palm=(meta['hand'][0]+30,meta['hand'][1]+15)
        phase=meta['phase']
        if name=='page-turn' and phase<2:
            arrow(draw,(point[0]-15,point[1]+27),(point[0]-133,point[1]+27))
        elif name=='finger-scroll' and phase==1:
            arrow(draw,(point[0]+36,point[1]+55),(point[0]+36,point[1]-40))
        elif name=='grab-drag' and phase==1:
            arrow(draw,(palm[0]+60,palm[1]-30),(palm[0]+110,palm[1]-68))
        elif name=='pinch-select':
            draw.line((palm,point),fill=ACCENT,width=2)
            draw.ellipse((point[0]-8,point[1]-8,point[0]+8,point[1]+8),outline=ACCENT,width=3)
        draw.text((W/2,579),title,anchor='mt',font=font(26,True),fill=INK)
        draw.text((W/2,624),line1,anchor='mt',font=font(18),fill=MUTED)
        draw.text((W/2,650),line2,anchor='mt',font=font(18),fill=MUTED)
        frames.append(image.convert('RGB'))
    atlas=Image.new('RGB',(W*4,H))
    for i in range(4): atlas.paste(frames[round(i*(len(frames)-1)/3)],(i*W,0))
    palette=atlas.quantize(colors=256,method=Image.Quantize.MEDIANCUT)
    encoded=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames]
    encoded[0].save(output/f'{name}.gif',save_all=True,append_images=encoded[1:],duration=[350]+[45]*(len(frames)-2)+[700],loop=0,disposal=1,optimize=True)
    frames[42].save(args.frames/f'{name}-review.png')
    print(name, len(frames), (output/f'{name}.gif').stat().st_size)
