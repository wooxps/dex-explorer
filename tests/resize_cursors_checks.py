"""Guard decoded cursor pixels, orientation and CUR hotspot alignment."""
import argparse
import hashlib
import io
from pathlib import Path
import re
import subprocess
import tempfile
from PIL import Image

cli = argparse.ArgumentParser()
cli.add_argument('--luau', default='luau')
args = cli.parse_args()
root = Path(__file__).resolve().parents[1]
assets = (root / 'studio_assets.lua').read_text()
for direction, digest in [('nwse', '3306219d72cf4e0ce39aa4abe33f03357470d77befed793e1c90927c6564d5be'),
                          ('nesw', '79d7acedc83d45cdfcb396cfa223dc7d4cc8d262b24b5817598796e3c5fb7eac')]:
    key = 'cursor/windows_resize_' + direction + '_32'
    literal = re.findall(r'\["' + key + r'"\] = "([^"\n]*)"', assets)
    assert len(literal) == 1
    raw = bytes(int(n) for n in re.findall(r'\\(\d{3})', literal[0]))
    image = Image.open(io.BytesIO(raw)).convert('RGBA')
    assert image.size == (32, 32)
    assert hashlib.sha256(image.tobytes()).hexdigest() == digest, direction
lib = (root / 'src/Shared/Lib.lua').read_text()
body = lib[lib.index('\t\tlocal function resizeCursorInfo('):lib.index('\n\t\tlocal function currentMousePosition(')]
body += '''
for _,dir in {"N","S","V","E","W","H","NE","SW","NW","SE"} do
 local key,rotation,size,x,y=resizeCursorInfo(dir)
 assert(rotation==0 and size==32,"native cursors must not be rotated or resized")
 if #dir==2 then
  local diagonal=(dir=="NE" or dir=="SW") and "nesw" or "nwse"
  assert(key=="cursor/windows_resize_"..diagonal.."_32" and x==8 and y==8,"corner image and original CUR hotspot")
 else
  assert(key:find("cursor/qt_split_",1,true) and x==nil and y==nil,"side cursor remains unchanged")
 end
end
'''
with tempfile.TemporaryDirectory() as folder:
    target = Path(folder) / 'cursors.luau'
    target.write_text(body)
    subprocess.run([args.luau, str(target)], check=True)
assert 'Vector2.new((hotX or size / 2) / size, (hotY or size / 2) / size)' in lib
print('PASS: original diagonal cursor RGBA, both orientations, native hotspots and unchanged side cursors')
