"""preview_helmets.py <out.gif> <unit>:<helmet> ...: helmets riding units walk2 (4 facings, bare | helmet), seated at each frame eye midpoint (aim.json). Free."""
import json, sys
from PIL import Image, ImageDraw
B = "assets/units/base_male_hi/source/"
G = "assets/gear/armor/helmet_%s/"
K = 3; W, H = 52, 64
clip = "walk2"
pairs = [a.split(":") for a in sys.argv[2:]]
FS = ["SE", "SW", "NE", "NW"]
frames = []
for i in range(8):
    o = Image.new("RGBA", (len(FS) * 2 * W * K, len(pairs) * H * K), (40, 42, 58, 255))
    for r, (u, hm) in enumerate(pairs):
        meta = json.load(open(G % hm + "attach.json"))
        for c, F in enumerate(FS):
            d = B + "%s_%s_%s" % (u, clip, F)
            j = json.load(open(d + "/aim.json"))["joints"]
            n = len(j); f = i % n
            im = Image.open(d + "_clean/frame_%03d.png" % f).convert("RGBA")
            on = im.copy()
            hp = Image.open(G % hm + F + ".png")
            ex = (j[f]["LEFT EYE"][0] + j[f]["RIGHT EYE"][0]) / 2; ey = (j[f]["LEFT EYE"][1] + j[f]["RIGHT EYE"][1]) / 2
            g = meta["grips"][F]
            on.alpha_composite(hp, (int(round(ex - g[0])), int(round(ey - g[1]))))
            for k, pic in enumerate((im, on)):
                cr = pic.crop((22, 12, 22 + W, 12 + H)).resize((W * K, H * K), Image.NEAREST)
                o.alpha_composite(cr, ((c * 2 + k) * W * K, r * H * K))
        ImageDraw.Draw(o).text((4, r * H * K + 2), "%s + %s" % (u, hm), fill=(255, 255, 255))
    frames.append(o.convert("RGB"))
frames[0].save(sys.argv[1], save_all=True, append_images=frames[1:], duration=120, loop=0)
frames[0].save(sys.argv[1].replace(".gif", "_f0.png"))
