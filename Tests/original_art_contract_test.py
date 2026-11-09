"""Verify every imported baked crop with stdlib PNG decoding, also on Apple CI."""
from pathlib import Path
import hashlib,json,re,struct,zlib
ROOT=Path(__file__).resolve().parents[1]
engine=ROOT/'SharedEngine'
data=(engine/'app/res/textures/original_art.png').read_bytes()
pos=8;packed=b''
while pos<len(data):
    n=struct.unpack('>I',data[pos:pos+4])[0];kind=data[pos+4:pos+8];chunk=data[pos+8:pos+8+n];pos+=n+12
    if kind==b'IHDR':w,h,depth,colour,_,_,interlace=struct.unpack('>IIBBBBB',chunk)
    if kind==b'IDAT':packed+=chunk
assert (w,h,depth,colour,interlace)==(2048,2048,8,6,0)
decoded=zlib.decompress(packed);stride=w*4;previous=bytearray(stride);rows=[];offset=0
for y in range(h):
    mode=decoded[offset];row=bytearray(decoded[offset+1:offset+1+stride]);offset+=stride+1
    for i in range(stride):
        a=row[i-4] if i>=4 else 0;b=previous[i];c=previous[i-4] if i>=4 else 0
        if mode==1:value=a
        elif mode==2:value=b
        elif mode==3:value=(a+b)//2
        elif mode==4:
            p=a+b-c;da,db,dc=abs(p-a),abs(p-b),abs(p-c)
            value=a if da<=db and da<=dc else b if db<=dc else c
        else:value=0
        row[i]=(row[i]+value)&255
    rows.append(row);previous=row
text=(engine/'app/src/game/original_art_data.h').read_text()
records=[list(map(float,s.replace('f','').split(','))) for s in re.findall(r'\{([\d.,f-]+)\}',text)]
receipt=json.loads((ROOT/'Scripts/original-art-receipt.json').read_text())
assert len(records)==len(receipt['crops'])==581
for rect,crop in zip(records,receipt['crops']):
    x,y,width,height=map(int,rect[:4])
    pixels=b''.join(row[x*4:(x+width)*4] for row in rows[y:y+height])
    assert hashlib.sha256(pixels).hexdigest()==crop['sha256'],crop
prepared=ROOT/'build-original-source/app/src'
assert 'original_hud_add' in (prepared/'rendering/renderer.c').read_text()
assert 'VK_BLEND_FACTOR_ONE : VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA' in (prepared/'rendering/spr_renderer.c').read_text()
assert '127.5f+colour.raw[j]*255*.64f' in (prepared/'game/redraw.c').read_text()
print('Original art: all 581 baked crops byte-identical; glyph metrics and additive pass hooks present')

# OM's follow-up: every texture uses the same slider and snake-relative d.
# The old baked-art size formula and const-size path deliberately no longer apply.
redraw=(prepared/'game/redraw.c').read_text()
assert 'float food_scale = gdata->data.gsc;' in redraw
assert redraw.count('float d = gdata->fsz[fo->cv2] * food_scale * fo->rad * mode->food_scale;')==2
assert redraw.count('original_food(usr->r,fx+d*.5f,fy+d*.5f,d,c,fo->fr,')==2
food=redraw[redraw.index('  if (mode->uniform_food_color)'):redraw.index('  /* Battledome letters and dome:')]
assert 'blend' not in food and 'fgsc' not in food and 'osz' not in food
assert 'float scale = diameter/52.0f;' in (prepared/'game/original_art.h').read_text()
for zoom in (.025,1.5,10):
    normal=11*zoom
    sheet_half_light=52*(normal/52)
    assert abs(sheet_half_light/normal-1)<1e-12
    assert abs(normal/(29*zoom)-11/29)<1e-12

renderer=(prepared/'rendering/renderer.c').read_text()
cursor=renderer[renderer.index('void renderer_render_cursor('):renderer.index('void renderer_render_cursor(')+1100]
assert cursor.index('r->overlay_text,') < cursor.index('r->overlay_text_add,') < cursor.index('r->cr,')
sheet=(prepared/'game/sheet_text.h').read_text()
assert 'face + (pass == 0 ? 1 : 0)' in sheet
assert 'pass == 0 || !face_add ? wyrm_text_normal : wyrm_text_add' in sheet
# Main.as drawText: every outline before every face; names NORMAL at .75.
draw_fn=sheet[sheet.index('static inline void sheet_draw('):sheet.index('static inline void sheet_layer(')]
assert draw_fn.index('for (int pass = 0; pass < 2; ++pass)') < draw_fn.index('for (const unsigned char* p')
assert 'sheet_draw(draw, text, size, pos, colour, font, 1.0f, true);' in sheet
assert 'SHEET_THIN, 0.75f, false);' in redraw
assert 'roundf(127.5f + scolor->r*255*.64f)' in redraw
# Stage3D keeps textures premultiplied; Starling BILINEAR = linear + MIPNEAREST, CLAMP.
texture=(prepared/'rendering/texture.c').read_text()
assert 'const bool premultiply = strstr(filename, "original_art") != NULL;' in texture
assert '(stbi_uc)((data[i * 4 + k] * a + 127) / 255)' in texture
spr=(prepared/'rendering/spr_renderer.c').read_text()
assert spr.count('original ? VK_BLEND_FACTOR_ONE : VK_BLEND_FACTOR_SRC_ALPHA')==2
assert 'colour.r*colour.a, colour.g*colour.a, colour.b*colour.a, colour.a' in (prepared/'game/original_art.h').read_text()
assert 'tint = {{rgb.r*a*veil, rgb.g*a*veil, rgb.b*a*veil, a}}' in sheet
assert '.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,' in renderer[renderer.index('&r->atlas_sampler);'):renderer.index('&r->sheet_sampler);')]
assert '{r->sheet_sampler,r->original_art_tex->view,' in renderer
assert 'wyrm_sheet_veil = usr->gdata.curr_screen == PLAYING && android_home_death_pending()' in (prepared/'main.c').read_text()
assert 'ImDrawList_GetClipRectMin' in sheet and 'ImDrawList_GetClipRectMax' in sheet
assert 'x < lo.x || y < lo.y || x+g->w*s > hi.x || y+g->h*s > hi.y' in sheet
assert 'float scale = size * SHEET_EM / 52.0f;' in sheet
board=(prepared/'game/ui_overlay.c').read_text()
assert 'float row_tail = fmaxf(0, em*(84.0f/52.0f)-9*sy);' in board
assert 'ImDrawList_PushClipRect(draw,(ImVec2){0,row_top},\n            (ImVec2){at.x+(28+165)*sx,bottom},true);' in board
# The outline extends left of the name pen; clipping there would eat its first
# letter. The last steady 5/10 row needs its baked descender/outline allowance.
for size in (.75,1):
    em=11*size; sy=size
    tail=max(0,em*84/52-9*sy)
    for count in (5,10):
        for glyph in records[285:570]:
            if len(glyph)!=9 or glyph[2]<=1: continue
            last_bottom=(5+14*(count-1))*sy+(glyph[3]-glyph[5])*glyph[6]*em/52
            assert last_bottom <= 14*count*sy+tail+1e-9
print('Overlay and food: paired passes, glyph clip guards, common zoom/slider diameter contracts passed')
