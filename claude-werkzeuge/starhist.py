import sys
from PIL import Image
names = [('dunkel', 0x114), ('blau', 0x125), ('braun', 0x631), ('gruen', 0x371),
         ('orange', 0x842), ('hell', 0xc84), ('weiss', 0xfdb)]
def rgb(c):
    return (((c >> 8) & 15) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17)
cols = {rgb(c): n for n, c in names}
d = sys.argv[1]
print('frame  ' + ' '.join('%6s' % n for n, _ in names))
for f in sys.argv[2].split(','):
    im = Image.open('%s/cop%s.png' % (d, f)).convert('RGB')
    w, h = im.size
    cnt = {n: 0 for n, _ in names}
    px = im.load()
    for y in range(h // 3, h):
        for x in range(w):
            n = cols.get(px[x, y])
            if n:
                cnt[n] += 1
    print('%5s  ' % f + ' '.join('%6d' % cnt[n] for n, _ in names))
