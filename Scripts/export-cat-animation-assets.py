#!/usr/bin/env python3
"""Deterministically export DockCat Orange v1 PNG frames from text source.

This script intentionally is not run during app startup. It exists so maintainers can
materialize the runtime PNG atlas locally without committing binary files to systems
that reject binary PR diffs.
"""
from pathlib import Path
import json, math, os, struct, zlib
W, H = 300, 220
OUT = Path("Sources/DockCat/Resources/CatAnimations/DockCatCat.atlas")
CLIPS = [('sleep',10,.16,'loop'),('wake',10,.08,'once'),('pickUp',10,.08,'once'),('turnToPresentation',8,.07,'once'),('walkCarry',10,.08,'loop'),('present',8,.08,'once'),('wait',8,.18,'loop'),('turnHome',8,.07,'once'),('walkHome',10,.08,'loop'),('settle',10,.1,'once')]
ORANGE=(235,132,42,255); LIGHT=(250,170,78,255); DARK=(70,44,34,255); SHADE=(190,94,33,255); CREAM=(255,216,145,255); PINK=(238,125,126,255)
def blend(px,c):
    r,g,b,a=c; A=a/255
    return (int(r*A+px[0]*(1-A)),int(g*A+px[1]*(1-A)),int(b*A+px[2]*(1-A)),int(255*A+px[3]*(1-A)))
def ellipse(img,cx,cy,rx,ry,c):
    for y in range(max(0,int(cy-ry)),min(H,int(cy+ry)+1)):
        for x in range(max(0,int(cx-rx)),min(W,int(cx+rx)+1)):
            if ((x-cx)/rx)**2+((y-cy)/ry)**2<=1: img[y][x]=blend(img[y][x],c)
def line(img,x1,y1,x2,y2,w,c):
    steps=int(max(abs(x2-x1),abs(y2-y1)))+1
    for i in range(steps):
        t=i/max(1,steps-1); ellipse(img,x1+(x2-x1)*t,y1+(y2-y1)*t,w,w,c)
def save(path,img):
    raw=b''.join(b'\x00'+bytes(sum(row,())) for row in img)
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',W,H,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))
def frame_name(name,i):
    return 'cat_'+{'pickUp':'pickup','turnToPresentation':'turn_presentation','walkCarry':'walk_carry','turnHome':'turn_home','walkHome':'walk_home'}.get(name,name)+f'_{i:03d}'
def draw(name,i,n):
    img=[[(0,0,0,0) for _ in range(W)] for __ in range(H)]
    p=i/n; cyc=math.sin(2*math.pi*p); body_y=132+(4*cyc if name in ['walkCarry','walkHome'] else 2*cyc if name=='sleep' else 0); head_y=94+(3*cyc if name in ['walkCarry','walkHome'] else 2*cyc if name=='wait' else 1*cyc if name=='sleep' else 0)
    if name=='wake': body_y=140-8*p; head_y=112-18*p
    if name=='settle': body_y=132+7*p; head_y=94+18*p
    carry=name in ['pickUp','turnToPresentation','walkCarry','present','wait']
    line(img,76,130,45,104,8,DARK); line(img,45,104,60,83,8,DARK); line(img,76,130,45,104,5,ORANGE); line(img,45,104,60,83,5,LIGHT)
    ellipse(img,130,body_y,55,34,DARK); ellipse(img,130,body_y,49,28,ORANGE); ellipse(img,143,body_y+4,28,17,CREAM)
    for lx in [104,145]:
        off=8*math.sin(2*math.pi*p+(0 if lx==104 else math.pi)) if name in ['walkCarry','walkHome'] else 0
        ellipse(img,lx+off,162,15,9,DARK); ellipse(img,lx+off,160,12,7,LIGHT)
    ellipse(img,170,head_y,42,33,DARK); ellipse(img,170,head_y,36,27,ORANGE); ellipse(img,183,head_y+10,15,10,CREAM)
    for sx in [-14,0,14]: line(img,170+sx,head_y-24,170+sx-5,head_y-13,2,SHADE)
    eye_open=not (name=='sleep' or (name=='wake' and p<.35) or (name=='settle' and p>.65))
    if eye_open: ellipse(img,159,head_y-5,4,6,DARK); ellipse(img,184,head_y-5,4,6,DARK)
    else: line(img,154,head_y-5,164,head_y-4,1,DARK); line(img,179,head_y-4,190,head_y-5,1,DARK)
    ellipse(img,173,head_y+6,3,2,PINK)
    pawx=214 if carry else 168
    if name=='pickUp': pawx=168+(214-168)*p
    if name=='present': pawx=214+10*p
    if name=='turnHome': pawx=224-40*p
    ellipse(img,pawx,145,13,8,DARK); ellipse(img,pawx,143,10,6,LIGHT)
    if carry: ellipse(img,244,148+(2*cyc if name in ['walkCarry','wait'] else 0),8,5,LIGHT)
    return img
def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest={"schemaVersion":1,"assetSetID":"dockcat.orange.v1","assetSetVersion":"1.0.0","atlasName":"DockCatCat","logicalCanvasSize":{"width":150,"height":110},"nativeScale":2,"anchors":{"visualAnchor":{"x":75,"y":35},"feetAnchor":{"x":75,"y":35},"carryAnchor":{"x":117,"y":73},"handoffSize":{"width":36,"height":24},"artworkBounds":{"x":18,"y":18,"width":244,"height":164}},"orientationPolicy":"canonicalRightFacingMirrorLeftRotateVertical","clips":[]}
    for name,n,sec,play in CLIPS:
        frames=[]
        for i in range(n):
            base=frame_name(name,i); frames.append(base); save(OUT/(base+'@2x.png'), draw(name,i,n))
        manifest['clips'].append({'id':name,'frameNames':frames,'secondsPerFrame':sec,'playback':play,'restorePolicy':'preserveFinalFrame'})
    res=OUT.parent; res.mkdir(parents=True, exist_ok=True); (res/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
if __name__ == '__main__': main()
