#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
# gx_snd_consts.py -- the sound constants of the sound leaves (filter coefficients, VCO tables),
# from the schematic's part values (M p.22 zones 13-16; the Nichibutsu MC-1 rows from MCS PDF 20) and MAME
# galaxian_a.cpp.
import math
fs_osc=24.576e6/16   # ce_1m5
fs=24.576e6/512      # 48 kHz
dt=1/fs_osc
# background DAC (MAME DAC_R1): bits0..3 = R18 1M, R17 470K, R16 220K, R15 100K; von 4.0, vbias 4.4 via R20 15K, rgnd R19 330K
R=[1e6,470e3,220e3,100e3]; Rb=15e3; Rg=330e3
gt=sum(1/r for r in R)+1/Rb+1/Rg
print("LFO: code V_dac i(uA) f(Hz) dv_per_1m5_step(V) Q16.16-of-V-step")
for code in range(16):
    v=(sum(4.0/R[i] for i in range(4) if code>>i&1)+4.4/Rb)/gt
    i=(5.0-(v+0.7))/100e3
    if i<0:i=0
    dv=i/1e-6*dt
    f=i/(1e-6*5/3)
    print(code,round(v,4),round(i*1e6,4),round(f,4),dv,round(dv*2**24))
print("CV = clamp(%.5f*v - %.5f,0,5)"%(10/ (1/(1/47e3+1/47e3+1/10e3)) /1e0 * 1e0, 5*10/47))
k=10e3/(1/(1/47e3+1/47e3+1/10e3)); print("gain",k, "offset",5*10/47)
def a(tau,f): return 1-math.exp(-1/(f*tau))
for name,ra,rb,c in (("8R",100e3,470e3,0.01e-6),("8S",100e3,330e3,0.01e-6),("8T",100e3,220e3,0.01e-6),("7S fire",10e3,22e3,0.01e-6),
                     ("8R MC-1",100e3,470e3,0.1e-6),("8S MC-1",100e3,330e3,0.1e-6),("8T MC-1",100e3,220e3,0.1e-6)):
    ach=a((ra+rb)*c,fs_osc); adis=a(rb*c,fs_osc)
    def f(cv):
        th=(ra+rb)*c*math.log((5-cv/2)/(5-cv)); tl=rb*c*math.log(2); return 1/(th+tl)
    print(name,"a_ch=%.6e (Q24 %d) a_dis=%.6e (Q24 %d) f(cv=1.31)=%.1f f(3.33)=%.1f f(3.69)=%.1f"%(ach,round(ach*2**24),adis,round(adis*2**24),f(1.312),f(3.333),f(3.687)))
for name,tau in (("C28/R47 fire env",2.2e3*47e-6),("C25 charge R90",1e3*1e-6),("C25 disch R41",100e3*1e-6),("C21 charge R89",1e3*2.2e-6),("C21 disch R35+R36",172e3*2.2e-6),("C21 disch MC-1 R35+node",(150e3+1/(1/2e3+3/10e3+1/33e3))*2.2e-6),("C20 bg mix (3x10K)",10e3/3*0.1e-6),("C29 CV node",1/(1/10e3+1/2.2e3+1/3333.3)*0.01e-6),("C46/R91 HPF",10e3*0.1e-6)):
    al=a(tau,fs); print("%-22s tau=%.4g s  alpha48k=%.6e Q24=%d"%(name,tau,al,round(al*2**24)))
# MFB bandpass
R1,R2,R4,C1,C2=150e3,22e3,470e3,0.01e-6,0.01e-6
w0=math.sqrt((R1+R2)/(R1*R2*R4*C1*C2)); f0=w0/2/math.pi
Q=w0/((1/C1+1/C2)/R4)
G0=R4*C1/(R1*(C1+C2))
print("hit bandpass f0=%.2f Hz Q=%.3f centre gain=-%.4f"%(f0,Q,G0))
# bilinear biquad
K=math.tan(math.pi*f0/fs); 
# analog H(s)= -(s/(R1C1)) / (s^2 + s*(1/C1+1/C2)/R4 + 1/(R4C1C2)*(1/R1+1/R2))
b1a=-1/(R1*C1); a1a=(1/C1+1/C2)/R4; a0a=(1/R1+1/R2)/(R4*C1*C2)
Tt=1/fs; c=2/Tt
# H(z): s=c(1-z^-1)/(1+z^-1)
B0=b1a*c; B1=0; B2=-b1a*c
A0=c*c+a1a*c+a0a; A1=2*a0a-2*c*c; A2=c*c-a1a*c+a0a
print("biquad b0=%.8f b1=0 b2=%.8f a1=%.8f a2=%.8f"%(B0/A0,B2/A0,A1/A0,A2/A0))
# fire CV network thevenin incl 555 internal 5K divider
print("fire 555 7S free-run f(cv=3.333)=%.1f"%(1/((32e3*1e-8)*math.log(2)+22e3*1e-8*math.log(2))))
import math
fs=48000.0; fo=24.576e6/16
R=[1e6,470e3,220e3,100e3]; gt=sum(1/r for r in R)+1/15e3+1/330e3
inc=[]
for c in range(16):
    v=(sum(4.0/R[i] for i in range(4) if c>>i&1)+4.4/15e3)/gt
    i=max(0,(5-(v+0.7))/100e3); inc.append(round(i/1e-6/fs*2**24))
print("LFO INC48k Q24:",inc)
a=lambda tau,f:1-math.exp(-1/(f*tau))
for n,t in (("C29 cv @1m5",1/(1/10e3+1/2.2e3+1/3333.33)*0.01e-6),("C25 ch R90 @1m5",1e-3),("C25 dis R41 @1m5",0.1)):
    print(n,a(t,fo),round(a(t,fo)*2**24),round(a(t,fo)*2**28))
# fire CV range with internal divider
for noise in (0,1):
    for e in (0.0,4.0):
        G=1/10e3+1/2.2e3+1/3333.33; I=noise*4.0/10e3+e/2.2e3+3.33333/3333.33
        cv=I/G
        th=32e3*1e-8*math.log((5-cv/2)/(5-cv)); tl=22e3*1e-8*math.log(2)
        mame=(noise*4/10e3+e/2.2e3)*(1/(1/10e3+1/2.2e3))
        print("noise",noise,"env",e,"cv=%.3f f=%.0f Hz | MAME cv=%.3f"%(cv,1/(th+tl),mame))
# speech filter stage params
import cmath
print("RC1 fc",1/(2*math.pi*2.2e3*33e-9))
for (r1,r2,c1,c2) in ((2.2e3,2.2e3,68e-9,3.3e-9),(3.3e3,3.3e3,0.1e-6,3.3e-9)):
    w=1/math.sqrt(r1*r2*c1*c2); q=math.sqrt(r1*r2*c1*c2)/((r1+r2)*c2); print("SK f0=%.0f Q=%.2f"%(w/2/math.pi,q))
# mixer weights galaxian
R51,R50,R49,R52,R34,R40,R43,R91=33e3,22e3,10e3,15e3,5.1e3,2.2e3,2.2e3,10e3
print("pre-mix conductances uS: QA %.2f QC %.2f QCv1 %.2f QDv2 %.2f BG %.2f"%(1e6/R51,1e6/R50,1e6/R49,1e6/R52,1e6/R34))
print("final: pre %.2f hit %.2f fire %.2f load %.2f"%(1e6/R34,1e6/R40,1e6/R43,1e6/R91))
print("moon: BG %.2f (R34=15K)"%(1e6/15e3))
print("speech/main weight (47K vs 22K):",22/47)
