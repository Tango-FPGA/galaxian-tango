#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
# gx_colour_levels.py -- the colour resistor-DAC, star and bullet levels of rtl/gx/gx_colour.v, from the
# Galaxian schematic's resistor values (M p.22 zones 13-16).
import math
G=lambda r:1.0/r
# ---- colour DAC: node = sum(G*V)/sum(G) incl 470 pulldown; driven high V=1, low V=0, open = absent
RPD=470.0
def node(drivers):  # list of (R, level 0/1)
    gs=sum(G(r) for r,_ in drivers)+G(RPD)
    return sum(G(r)*v for r,v in drivers)/gs
red_prom=[1000.0,470.0,220.0]   # bit0..2 ; green same; blue bit0..1 = 470,220
blue_prom=[470.0,220.0]
star_rg=(150.0,100.0)  # (lsb,msb)
def chan(prom_res, prom_en, prom_bits, star_en, star_bits, bul):  # bul: None, 1(high), 0(low)
    d=[]
    if prom_en:
        for i,r in enumerate(prom_res): d.append((r,(prom_bits>>i)&1))
    if star_en:
        d.append((150.0,star_bits&1)); d.append((100.0,(star_bits>>1)&1))
    if bul is not None: d.append((100.0,bul))
    return node(d)
vals={}
mx=0
for res,name in ((red_prom,'RG'),(blue_prom,'B')):
    for bul in (None,1,0):
        for pe in (0,1):
            for pb in range(1<<len(res)) if pe else [0]:
                for se in (0,1):
                    for sb in range(4) if se else [0]:
                        if pe and se: continue
                        v=chan(res,pe,pb,se,sb,bul); mx=max(mx,v)
                        vals[(name,bul,pe,pb,se,sb)]=v
print("max node voltage (fraction of Voh):",mx)
scale=255.0/mx
def lv(v): return int(round(v*scale))
for name in ('RG','B'):
    print("==",name)
    for bul in (None,1,0):
        row=[]
        n=3 if name=='RG' else 2
        row.append("prom:"+",".join(str(lv(vals[(name,bul,1,pb,0,0)])) for pb in range(1<<n)))
        row.append("star:"+",".join(str(lv(vals[(name,bul,0,0,1,sb)])) for sb in range(4)))
        row.append("none:"+str(lv(vals[(name,bul,0,0,0,0)])))
        print(" bullet=",bul," ".join(row))
