#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
# gx_snd_coefs.py -- the fixed-point constants of the sound leaves gx_snd_bg, gx_snd_hit and gx_snd_fire
# computed from the schematic part values (Galaxian manual
# p.22 zones 12-16) with the formulas of tools/gx_snd_consts.py.
#
#   gx_snd_coefs.py                 print every constant as a Verilog localparam line
#   gx_snd_coefs.py --check F.v...  check that each localparam named here has this value in the given files
#   import gx_snd_coefs; gx_snd_coefs.C['BG_INC'] ...   (the Python goldens use the same values)
#
# Formats: voltages Q4.24 (V * 2^24), RC step factors alpha = 1 - exp(-dt/tau) in Q0.28 (the modules shift every
# product right by 28), the background CV gain in Q4.28, the hit band-pass coefficients Q2.28.
import math, os, re, sys

F_OSC = 24.576e6 / 16          # ce_1m5
F_S = 24.576e6 / 512           # ce_48k
Q24 = 1 << 24
Q28 = 1 << 28


def v24(x):
    return int(round(x * Q24))


def alpha(tau, f):
    return 1.0 - math.exp(-1.0 / (f * tau))


def a28(tau, f):
    return int(round(alpha(tau, f) * Q28))


def a24x16(tau, f):
    # the spec's Q0.24 value, carried in Q0.28 (x 16, the same number)
    return int(round(alpha(tau, f) * Q24)) * 16


C = {}
# ---- common
C['V5'] = v24(5.0)                                      # 555 supply
C['U_DIODE'] = v24(4.0 - 0.7)                           # TTL high 4.0 V minus a 1N4148 drop (MAME rcdisc5 0.7 V)

# ---- gx_snd_bg (3.16)
R_DAC = [1e6, 470e3, 220e3, 100e3]                      # R18, R17, R16, R15 (9M Q4..Q7)
R20, R19, R21, C15 = 15e3, 330e3, 100e3, 1e-6
g_tot = sum(1 / r for r in R_DAC) + 1 / R20 + 1 / R19
inc = []
for code in range(16):
    v_dac = (sum(4.0 / R_DAC[i] for i in range(4) if code >> i & 1) + 4.4 / R20) / g_tot
    i_cc = max(0.0, (5.0 - (v_dac + 0.7)) / R21)       # 555_CC current through R21 (Q2 junction 0.7 V)
    inc.append(int(round(i_cc / C15 / F_S * Q24)))
C['BG_INC'] = inc                                       # LFO ramp per 48 kHz step, Q4.24
C['BG_VTRIG'] = v24(5.0 / 3)                            # 9R trigger level
C['BG_VTHR'] = v24(10.0 / 3)                            # 9R threshold level
R31, R32, R33 = 47e3, 47e3, 10e3
C['BG_CVG'] = int(round(R33 * (1 / R31 + 1 / R32 + 1 / R33) * Q28))   # LM324 7T gain 1.425532, Q4.28
C['BG_CVOFF'] = v24(5.0 * R33 / R31)                    # 1.063830 V
C['BG_CVTOP'] = v24(5.0 - 1.5)                          # LM324 7T on +5 V (M p.22 note 5): high swing ~3.5 V
for name, ra, rb in (('8R', 100e3, 470e3), ('8S', 100e3, 330e3), ('8T', 100e3, 220e3)):
    C['BG_ACH_' + name] = a24x16((ra + rb) * 0.01e-6, F_OSC)
    C['BG_ADIS_' + name] = a24x16(rb * 0.01e-6, F_OSC)
# Nichibutsu MC-1 (MCS PDF 20, printed p.19): the same astables with C17 / C18 / C19 = 0.1 uF (mc1 = 1).  Q0.28 from
# the exact alpha (a Q0.24 value x 16 would be up to 0.26 % off at these sizes).
for name, ra, rb in (('8R', 100e3, 470e3), ('8S', 100e3, 330e3), ('8T', 100e3, 220e3)):
    C['BG_ACH_%s_MC1' % name] = a28((ra + rb) * 0.1e-6, F_OSC)
    C['BG_ADIS_%s_MC1' % name] = a28(rb * 0.1e-6, F_OSC)
C['BG_XUNIT'] = v24(4.5 / 96)                           # 4.5 V x count / 32 / 3 sources = 3/64 V per count
C['BG_AC20'] = a24x16(10e3 / 3 * 0.1e-6, F_S)          # 3 x 10K into C20 0.1 uF

# ---- gx_snd_hit (3.17)
C['HIT_ACH'] = a24x16(1e3 * 2.2e-6, F_S)                # R89 1K x C21 2.2 uF
C['HIT_ADIS'] = a24x16(172e3 * 2.2e-6, F_S)             # (R35 + R36) x C21
# MC-1 FLASH (MCS PDF 20): C21 discharges through R35 150K into the mixer node N while the 4066 is closed; N's
# resistance with VOL1 / VOL2 off and C20 / C26 open (VR 2K || R24 / R27 / R30 10K || R51 33K) is in series.
RN_MC1 = 1 / (1 / 2e3 + 3 / 10e3 + 1 / 33e3)
C['HIT_ADIS_MC1'] = a28((150e3 + RN_MC1) * 2.2e-6, F_S)
R1, R2, R4, CA, CB = 150e3, 22e3, 470e3, 0.01e-6, 0.01e-6   # R35, R36, R37, C22, C23
b1a = -1 / (R1 * CA)
a1a = (1 / CA + 1 / CB) / R4
a0a = (1 / R1 + 1 / R2) / (R4 * CA * CB)
cc = 2 * F_S                                            # bilinear, s = 2 fs (1 - z^-1) / (1 + z^-1)
A0 = cc * cc + a1a * cc + a0a
C['HIT_B0'] = int(round(b1a * cc / A0 * Q28))          # b2 = -b0, b1 = 0
C['HIT_NA1'] = int(round(-(2 * a0a - 2 * cc * cc) / A0 * Q28))   # -a1
C['HIT_NA2'] = int(round(-(cc * cc - a1a * cc + a0a) / A0 * Q28))  # -a2
C['HIT_VB'] = v24(5.0 * 22e3 / (33e3 + 22e3))           # R38 / R39 bias, 2.0 V
C['HIT_VTOP'] = v24(5.0 - 1.5)                          # LM324 high swing (MAME OP_AMP_VP_RAIL_OFFSET)

# ---- gx_snd_fire (3.18)
C['FIRE_A28'] = a24x16(2.2e3 * 47e-6, F_S)              # R47 x C28
C['FIRE_VENV'] = v24(4.0)                               # 8L output high
G_CV = 1 / 10e3 + 1 / 2.2e3 + 1 / (1 / (1 / 5e3 + 1 / 10e3))
C['FIRE_KE'] = int(round((1 / 2.2e3) / G_CV * Q28))      # e weight through R48
C['FIRE_CVB'] = v24((10.0 / 3) * (1 / (1 / (1 / 5e3 + 1 / 10e3))) / G_CV)   # 555 internal divider term
C['FIRE_NT'] = v24(4.0 * (1 / 10e3) / G_CV)             # NOISE through R46
C['FIRE_A29'] = a24x16(0.01e-6 / G_CV, F_OSC)          # C29 on the CV node
C['FIRE_ACH'] = a24x16((10e3 + 22e3) * 0.01e-6, F_OSC)  # 7S R44 + R45, C27
C['FIRE_ADIS'] = a24x16(22e3 * 0.01e-6, F_OSC)          # 7S R45, C27
C['FIRE_A25C'] = a24x16(1e3 * 1e-6, F_OSC)              # R90 1K x C25 1 uF
C['FIRE_A25D'] = a28(100e3 * 1e-6, F_OSC)               # R41 100K x C25 (Q0.28: Q0.24's 109 is 0.2 % off)


def verilog_lines():
    out = []
    for k, v in C.items():
        if isinstance(v, list):
            continue
        out.append("localparam signed [31:0] %s = %d;" % (k, v))
    return out


# Constants each module must declare, by file name. A required name that is missing, or whose value is not a plain
# or sized decimal literal, is an error, so a renamed or reformatted constant cannot pass unchecked.
REQUIRED = {
    'gx_snd_bg': ['V5', 'BG_VTRIG', 'BG_VTHR', 'BG_CVG', 'BG_CVOFF', 'BG_CVTOP', 'BG_ACH_8R', 'BG_ADIS_8R',
                  'BG_ACH_8S', 'BG_ADIS_8S', 'BG_ACH_8T', 'BG_ADIS_8T', 'BG_AC20', 'BG_ACH_8R_MC1', 'BG_ADIS_8R_MC1',
                  'BG_ACH_8S_MC1', 'BG_ADIS_8S_MC1', 'BG_ACH_8T_MC1', 'BG_ADIS_8T_MC1'],
    'gx_snd_hit': ['U_DIODE', 'HIT_ACH', 'HIT_ADIS', 'HIT_ADIS_MC1', 'HIT_B0', 'HIT_NA1', 'HIT_NA2', 'HIT_VB',
                   'HIT_VTOP'],
    'gx_snd_fire': ['V5', 'U_DIODE', 'FIRE_A28', 'FIRE_VENV', 'FIRE_KE', 'FIRE_CVB', 'FIRE_NT', 'FIRE_A29',
                    'FIRE_ACH', 'FIRE_ADIS', 'FIRE_A25C', 'FIRE_A25D'],
}

# NAME = 123, NAME = -123, NAME = 32'sd123, NAME = -32'sd123; any other right-hand side is reported as unreadable.
_VAL = r"(-?)\s*(?:\d+\s*'\s*[sS]?\s*[dD]\s*)?(\d+)\b(?!\s*')"


def _values(txt, name):
    out = []
    for m in re.finditer(r"\b%s\s*=(?!=)\s*([^;,\n]*)" % name, txt):
        v = re.match(r"\s*" + _VAL + r"\s*$", m.group(1))
        out.append(None if v is None else int(v.group(1) + v.group(2)))
    return out


def check(paths):
    bad = 0
    for p in paths:
        txt = re.sub(r"//[^\n]*", "", open(p).read())
        txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.S)
        mod = os.path.splitext(os.path.basename(p))[0]
        for k in REQUIRED.get(mod, []):
            if not re.search(r"\blocalparam\b[^;]*\b%s\s*=" % k, txt):
                print("%s: %s missing (must be a localparam with this exact name)" % (p, k)); bad += 1
        for k, v in C.items():
            if isinstance(v, list):
                for i, x in enumerate(v):
                    for got in _values(txt, "%s_%d" % (k, i)):
                        if got != x:
                            print("%s: %s_%d = %s, expected %d" % (p, k, i, got, x)); bad += 1
                continue
            for got in _values(txt, k):
                if got is None:
                    print("%s: %s has an unreadable value (use a decimal literal)" % (p, k)); bad += 1
                elif got != v:
                    print("%s: %s = %s, expected %d" % (p, k, got, v)); bad += 1
    print("gx_snd_coefs: %s" % ("all localparams match" if bad == 0 else "%d mismatches" % bad))
    return bad


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--check':
        sys.exit(1 if check(sys.argv[2:]) else 0)
    for line in verilog_lines():
        print(line)
    print("// BG_INC = %s" % C['BG_INC'])
