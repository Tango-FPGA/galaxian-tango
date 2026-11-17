#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
# gx_mix_coefs.py -- the fixed-point constants of gx_snd_mix (rtl/gx/gx_snd_mix.v), computed from the
# part values of each board's mixer and output network, and a bit-exact Python model of the module.
#
#   gx_mix_coefs.py                 print the constants (localparam lines) and the coefficient table
#   gx_mix_coefs.py --check F.v...  check that each localparam named here has this value in the given files, and that
#                                   the coefficient table between the BEGIN / END markers is the one generated here
#   gx_mix_coefs.py --table         print each board's per-source response, model vs the continuous network
#   import gx_mix_coefs; gx_mix_coefs.C[...], gx_mix_coefs.Mix().step(...)   (the bit-exact model)
#
# Boards (cfg = {board[1:0], vol2, vol1}):
#   0 GAL  Galaxian (M p.22 z12-16).  Background: the 8R / 8S / 8T outputs through R24 / R27 / R30 10K into node A,
#          C20 0.1 uF from A to ground (z13), upper R34 5.1K from A to the AUDIO bus P (z13).  Pitch: QA R51 33K, QC
#          R50 22K, QC through the VOL1 4066 R49 10K, QD through the VOL2 4066 R52 15K, all into P (z10-11).  Lower R34
#          5.1K from P to the final node N (z14); HIT op-amp through R40 2.2K, FIRE buffer through C26 0.01 uF and R43
#          2.2K, R91 10K (the volume pot) from N to ground (z14-16).
#   1 MCG  Moon Cresta, Gremlin 800-3121 (MCG p1 zone B1): background node A with C20 0.01 uF (".01"), R34 15K from A
#          to the single node N; R51 / R50 / R49 / R52, R40 and R43 / C26 into N; no R91.  Used by Portman (mod 05),
#          whose own board is undocumented.
#   2 KB   King & Balloon (KB p14): as MCG with C20 0.1 uF (".1").
#   3 MC1  Nichibutsu MC-1 (MCS PDF 20, printed p.19): R24 / R27 / R30 10K join N itself, C20 0.1 uF on N, no R34;
#          pitch QA R51 33K direct, QC through a 4066 R49 10K ("f/4"), QD through a 4066 R52 15K ("f/8"), no R50; R43 /
#          C26; VR 2K (the volume pot) from N to ground, its wiper DC-coupled to the 9T amplifier.  The MC-1 FLASH
#          branch is R35 150K from the 4066-gated C21 (no band-pass); the H source here is gx_snd_hit's v_flash (that
#          gated C21, mc1 = 1) through that R35.  Used by Moon Quasar (mod 0F).
#
# The network.  Ideal sources: X, the mean of the three 555 outputs over the sample (each 4.5 V high, gx_snd_bg), behind
# R24 || R27 || R30 = 3.33K; QA / QC / QD, TTL 4.0 V high and 0 V low (MAME TTL_OUT), box-averaged over the sample
# (count of 32 ce_1m5 samples), combined into their Thevenin source J (J = sum g_k q_k / sum g_k behind 1 / sum g_k,
# the switched resistors leaving both sums when off); H, the HIT op-amp output (v_hit; MC1: v_flash); the FIRE buffer
# output (v_fire).
# Two states: vA, the voltage on C20, and vc, the voltage on C26 (fire side minus R43 side).  Nodal analysis with the
# capacitors as sources gives dx/dt = A x + B u and the node y = C x + D u, u = (X, J, H, F).  Every input is held for
# the 48 kHz step (each leaf output is a per-sample value), so the exact step is x' = Phi x + Gam u (Phi = e^(AT),
# Gam = A^-1 (Phi - I) B), and the step's mean node voltage is ym = Cm x + Dm u with Cm = C M,
# Dm = C A^-1 (M - I) B + D, M = A^-1 (Phi - I) / T.  Pre-charge: on the first sample after reset the states start at
# the DC operating point of that sample's inputs, vA = GA u (C26 open), vc = v_fire - HD u (HD u: the node at DC), and
# the coupling state z at that sample's node voltage, so the first output sample is the settled value (0 after the
# coupling).
#
# X from bg.  gx_snd_bg outputs its own unloaded C20 node, bg[k] = bg[k-1] + A0 (X[k] - bg[k-1]) (A0 = BG_AC20 / 2^28,
# M p.22 z13, tau 333 us), floored to Q4.12, with X = m 3/64 V, m = 0..96 (three 555s, 32 counts each, 4.5 V / 96).
# The mixer recovers m = round(bg[k-1] / 192 + (bg[k] - bg[k-1]) / (192 A0)) in Q4.12 LSBs, clamped to 0..96: the floor
# of each bg sample puts at most 0.09 of a step into it, so m is exact.  On the pre-charge sample m = round(bg / 192).
#
# Output coupling, a first-order high-pass z += A46 (y' - z), out = y' - z, y' = ym (+ KS speech for K&B), exact up to a
# constant level factor (each network is driven from the node's Thevenin source; Rth = the node resistance with VOL1 /
# VOL2 off and C20 / C26 open):
#   GAL (M p.22 z16): R91 is the volume pot from N to ground; its wiper drives C46 0.1 uF into LM377 pin 6, which R92
#     100K returns to the C51 bias node.  tau = C46 (R92 + Rth).
#   MCG (MCG p1 zone B1): N drives C39 0.1 uF and R42 22K into the volume-control input, 1K to ground.
#     tau = C39 (Rth + R42 + 1K).
#   KB (KB p14 left, 02-70102): C29 0.1 uF and R42 22K into the 1K volume pot; SYNTHE (the speech board's R33 47K, KB
#     p15) joins at the pot's top.  tau = C29 (Rth + R42 + 1K || 47K).  The speech board output is DC-coupled to the pot
#     (no capacitor after IC16b, KB p15), so the speech shares the main path's high-pass: out = HP(ym + KS speech), with
#     KS = (Rth + R42) / R33, the speech's weight against the main path's open-circuit voltage at the pot.  KS is per
#     {vol2, vol1} (table entry KS, 0 for the other boards): Rth here is N's resistance with that VOL1 / VOL2 state
#     (R49 / R52 switched in), C20 / C26 open.
#   MC1 (MCS PDF 20): no coupling capacitor (N into the VR 2K pot, the wiper straight into 9T pin 6); the amplifier's
#     own low-frequency corner is not documented, so the DC is removed at MAME's mixer output coupling (C46 0.1 uF into
#     100K, tau 10 ms).
#
# Formats: voltages Q6.20 (V * 2^20) in 27-bit signed operands; coefficients Q0.17 signed (18 bits); products >>> 17.
# Output Q3.13 (V * 2^13, +-4 V full scale), rounded toward -inf and saturated; for K&B it is half the coupled voltage
# (>> 8 instead of >> 7): its speech peaks about 6 dB above every other game's loudest sound, and each board's own
# amplifier clips on its loudest sound unless its volume pot is set below that.
import math
import re
import sys

F_S = 24.576e6 / 512           # ce_48k
T = 1.0 / F_S
QF = 17
Q17 = 1 << QF

GAL, MCG, KB, MC1 = 0, 1, 2, 3
BOARDS = ("GAL", "MCG", "KB", "MC1")
RX = 10e3 / 3                  # R24 || R27 || R30
R40, R43, R49, R50, R51, R52 = 2.2e3, 2.2e3, 10e3, 22e3, 33e3, 15e3
R34G, R34M, R91, R35 = 5.1e3, 15e3, 10e3, 150e3
VR_MC1 = 2e3
C26 = 0.01e-6
C20 = {GAL: 0.1e-6, MCG: 0.01e-6, KB: 0.1e-6, MC1: 0.1e-6}
R92, C46 = 100e3, 0.1e-6                           # Galaxian LM377 bias resistor, C46
C39, R42M, R1KM = 0.1e-6, 22e3, 1e3                # Gremlin C39 / R42 / 1K
C29K, R42K, RVRK, R33K = 0.1e-6, 22e3, 1e3, 47e3   # K&B C29 / R42 / 1K VR; speech R33
TAU_MC1 = 100e3 * 0.1e-6                           # MAME's mixer output coupling (MC-1: none on the board)
BG_AC20 = 16263680                                 # gx_snd_bg's C20 coefficient, Q0.28 (checked against that file)
A0 = BG_AC20 / float(1 << 28)
BG_LSB_PER_STEP = 192                              # 3/64 V in Q4.12 LSBs

# coefficient table layout (index within a cfg)
KEYS = ["WA", "WC", "WD",
        "GA_X", "GA_J", "GA_H", "GA_F", "HD_X", "HD_J", "HD_H", "HD_F",
        "CM_A", "CM_C", "DM_X", "DM_J", "DM_H", "DM_F",
        "PA_A", "PA_C", "GM_A_X", "GM_A_J", "GM_A_H", "GM_A_F",
        "PC_A", "PC_C", "GM_C_X", "GM_C_J", "GM_C_H", "GM_C_F", "KS"]
KIDX = {k: i for i, k in enumerate(KEYS)}


# ---- small dense linear algebra (stdlib only)
def solve(a, b):
    """Solve a x = b (a: n x n, b: n x m lists), Gaussian elimination with partial pivoting."""
    n = len(a)
    m = [list(a[i]) + list(b[i]) for i in range(n)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                m[r] = [x - f * y for x, y in zip(m[r], m[c])]
    return [[x / m[i][i] for x in m[i][n:]] for i in range(n)]


def mmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(len(b))) for j in range(len(b[0]))] for i in range(len(a))]


def madd(a, b, s=1.0):
    return [[x + s * y for x, y in zip(ra, rb)] for ra, rb in zip(a, b)]


def eye(n):
    return [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]


def expm(a):
    """e^a by scaling and squaring of the Taylor series (small, well-conditioned matrices)."""
    nrm = max(sum(abs(x) for x in r) for r in a)
    s = max(0, int(math.ceil(math.log2(nrm))) + 4) if nrm > 0 else 0
    a2 = [[x / (1 << s) for x in r] for r in a]
    e = eye(len(a)); term = eye(len(a))
    for k in range(1, 30):
        term = [[x / k for x in r] for r in mmul(term, a2)]
        e = madd(e, term)
    for _ in range(s):
        e = mmul(e, e)
    return e


# ---- the networks
def network(board, vol1, vol2):
    """Elements (a, b, R) between nodes; sources X J H F and ground g are ideal; 'A' carries C20 (the state vA),
    'FN' is the R43 side of C26 (V = F - vc).  Returns (elements, pitch Thevenin weights, node with C20)."""
    if board == MC1:
        gp = {'QA': 1 / R51, 'QC': vol1 / R49, 'QD': vol2 / R52}
    else:
        gp = {'QA': 1 / R51, 'QC': 1 / R50 + vol1 / R49, 'QD': vol2 / R52}
    gj = sum(gp.values())
    w = {k: v / gj for k, v in gp.items()}
    if board == GAL:
        el = [('X', 'A', RX), ('A', 'P', R34G), ('J', 'P', 1 / gj), ('P', 'N', R34G), ('H', 'N', R40),
              ('FN', 'N', R43), ('N', 'g', R91)]
        cnode = 'A'
    elif board in (MCG, KB):
        el = [('X', 'A', RX), ('A', 'N', R34M), ('J', 'N', 1 / gj), ('H', 'N', R40), ('FN', 'N', R43)]
        cnode = 'A'
    else:
        el = [('X', 'A', RX), ('J', 'A', 1 / gj), ('H', 'A', R35), ('FN', 'A', R43), ('A', 'g', VR_MC1)]
        cnode = 'A'
    return el, w, cnode


SRC = ('X', 'J', 'H', 'F')


def node_volts(el, fixed):
    """Node voltages of the resistive network with the given fixed node voltages (dict)."""
    nodes = sorted({n for e in el for n in e[:2]} - set(fixed) - {'g'})
    if not nodes:
        return dict(fixed, g=0.0)
    ix = {n: i for i, n in enumerate(nodes)}
    y = [[0.0] * len(nodes) for _ in nodes]; i_ = [[0.0] for _ in nodes]
    for a, b, r in el:
        g = 1 / r
        for p, q in ((a, b), (b, a)):
            if p in ix:
                y[ix[p]][ix[p]] += g
                if q in ix:
                    y[ix[p]][ix[q]] -= g
                elif q != 'g':
                    i_[ix[p]][0] += g * fixed[q]
    v = solve(y, i_)
    out = dict(fixed, g=0.0)
    out.update({n: v[ix[n]][0] for n in nodes})
    return out


def node_y(el):
    return 'A' if not any('N' in e[:2] for e in el) else 'N'


def statespace(board, vol1, vol2):
    """(A, B, C, D, weights) of dx/dt = A x + B u, y = C x + D u; x = (vA, vc), u = (X, J, H, F)."""
    el, w, cnode = network(board, vol1, vol2)
    yn = node_y(el)
    c20 = C20[board]
    cols = []
    for j in range(6):                              # vA, vc, X, J, H, F
        e = [0.0] * 6; e[j] = 1.0
        va, vc = e[0], e[1]
        fixed = {'A': va, 'X': e[2], 'J': e[3], 'H': e[4], 'F': e[5]}
        fixed['FN'] = e[5] - vc
        v = node_volts(el, fixed)
        ia = sum((v[b] - v[a]) / r if a == 'A' else (v[a] - v[b]) / r for a, b, r in el if 'A' in (a, b))
        i26 = (v['FN'] - v[yn]) / R43
        cols.append((ia / c20, i26 / C26, v[yn]))
    a = [[cols[0][0], cols[1][0]], [cols[0][1], cols[1][1]]]
    b = [[cols[j][0] for j in range(2, 6)], [cols[j][1] for j in range(2, 6)]]
    c = [[cols[0][2], cols[1][2]]]
    d = [[cols[j][2] for j in range(2, 6)]]
    return a, b, c, d, w


def rth(board, vol1=0, vol2=0):
    """Node resistance with the given VOL1 / VOL2, C20 and C26 open, sources at 0."""
    el, _, _ = network(board, vol1, vol2)
    yn = node_y(el)
    el = [e for e in el if 'FN' not in e[:2]]
    g1 = node_volts(el + [('INJ', yn, 1.0)], {'X': 0.0, 'J': 0.0, 'H': 0.0, 'F': 0.0, 'INJ': 1.0})[yn]
    return g1 / (1 - g1)                            # 1 V behind 1 ohm: V = Rth / (Rth + 1)


def discretise(board, vol1, vol2):
    a, b, c, d, w = statespace(board, vol1, vol2)
    at = [[x * T for x in r] for r in a]
    phi = expm(at)
    ainv = solve(a, eye(2))
    pm = mmul(ainv, madd(phi, eye(2), -1.0))        # A^-1 (Phi - I)
    gam = mmul(pm, b)
    m = [[x / T for x in r] for r in pm]
    cm = mmul(c, m)
    dm = madd(mmul(mmul(c, mmul(ainv, madd(m, eye(2), -1.0))), b), d)
    xdc = [[-x for x in r] for r in mmul(ainv, b)]  # DC states
    ydc = madd(mmul(c, xdc), d)
    return dict(phi=phi, gam=gam, cm=cm, dm=dm, xdc=xdc, ydc=ydc, w=w, a=a, b=b, c=c, d=d)


def q17(x):
    v = int(round(x * Q17))
    if v == Q17 and abs(x - 1.0) < 1e-12:
        v = Q17 - 1                                 # a weight of exactly 1 (MC-1 pitch with VOL1 / VOL2 off)
    assert -Q17 <= v < Q17, x
    return v


def cfg_coefs(board, vol1, vol2):
    s = discretise(board, vol1, vol2)
    f = {}
    f["WA"], f["WC"], f["WD"] = s["w"]['QA'], s["w"]['QC'], s["w"]['QD']
    for j, n in enumerate(SRC):
        f["GA_" + n] = s["xdc"][0][j]
        f["HD_" + n] = s["ydc"][0][j]
        f["DM_" + n] = s["dm"][0][j]
        f["GM_A_" + n] = s["gam"][0][j]
        f["GM_C_" + n] = s["gam"][1][j]
    f["CM_A"], f["CM_C"] = s["cm"][0]
    f["PA_A"], f["PA_C"] = s["phi"][0]
    f["PC_A"], f["PC_C"] = s["phi"][1]
    f["KS"] = (rth(board, vol1, vol2) + R42K) / R33K if board == KB else 0.0
    return [q17(f[k]) for k in KEYS], f


TAB = {}                                            # cfg -> list of Q0.17 coefficients
FLT = {}
for board in range(4):
    for k in range(4):                              # k = {vol2, vol1}
        TAB[board * 4 + k], FLT[board * 4 + k] = cfg_coefs(board, k & 1, k >> 1)

RTH = {b: rth(b) for b in range(4)}
C = {}
C['MIX_KR0'] = q17(1.0 / BG_LSB_PER_STEP)
C['MIX_KR1'] = q17(1.0 / (BG_LSB_PER_STEP * A0))
C['MIX_A46_GAL'] = q17(1 - math.exp(-T / (C46 * (R92 + RTH[GAL]))))
C['MIX_A46_MCG'] = q17(1 - math.exp(-T / (C39 * (RTH[MCG] + R42M + R1KM))))
C['MIX_A46_KB'] = q17(1 - math.exp(-T / (C29K * (RTH[KB] + R42K + 1 / (1 / RVRK + 1 / R33K)))))
C['MIX_A46_MC1'] = q17(1 - math.exp(-T / TAU_MC1))
CHECK_EXTRA = {'BG_AC20': BG_AC20}                  # gx_snd_bg.v (the recursion the mixer inverts)


def sat16(x):
    return max(-32768, min(32767, x))


class Mix:
    """Bit-exact model of gx_snd_mix: one call of step() per ce_48k sample, with that sample's inputs."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.va = self.vc = self.z = 0
        self.bp = 0
        self.pre = 1
        self.audio = 0
        self.m = 0
        self.resid = 0.0

    @staticmethod
    def mul(a, c):
        return (a * c) >> QF

    def step(self, board, vol1, vol2, ca, cc, cd, bg, hit, fire, speech):
        """board 0..3 (GAL MCG KB MC1); ca/cc/cd: high counts 0..32; bg, fire: Q4.12 unsigned; hit: Q4.12 signed;
        speech: Q5.11 signed."""
        t = TAB[board * 4 + vol2 * 2 + vol1]
        cf = lambda k: t[KIDX[k]]
        mul = self.mul
        # X from bg (Q.17 of a step)
        if self.pre:
            r = bg * C['MIX_KR0']
        else:
            r = self.bp * C['MIX_KR0'] + (bg - self.bp) * C['MIX_KR1']
        m = (r + (1 << (QF - 1))) >> QF
        self.resid = abs(r / float(Q17) - m)        # not part of the module: the recovery's margin (exact below 0.5)
        m = 0 if m < 0 else 96 if m > 96 else m
        self.m = m
        self.bp = bg
        u = {'X': m * 49152, 'H': hit << 8, 'F': fire << 8}
        u['J'] = mul(ca << 17, cf('WA')) + mul(cc << 17, cf('WC')) + mul(cd << 17, cf('WD'))
        if self.pre:
            self.va = sum(mul(u[n], cf('GA_' + n)) for n in SRC)
            self.vc = u['F'] - sum(mul(u[n], cf('HD_' + n)) for n in SRC)
        y = mul(self.va, cf('CM_A')) + mul(self.vc, cf('CM_C')) + sum(mul(u[n], cf('DM_' + n)) for n in SRC)
        na = mul(self.va, cf('PA_A')) + mul(self.vc, cf('PA_C')) + sum(mul(u[n], cf('GM_A_' + n)) for n in SRC)
        nc = mul(self.va, cf('PC_A')) + mul(self.vc, cf('PC_C')) + sum(mul(u[n], cf('GM_C_' + n)) for n in SRC)
        self.va, self.vc = na, nc
        if board == KB:
            y += mul(speech << 9, cf('KS'))
        if self.pre:
            self.z = y
        else:
            a46 = C['MIX_A46_' + BOARDS[board]]
            self.z += mul(y - self.z, a46)
        self.pre = 0
        self.audio = sat16((y - self.z) >> (8 if board == KB else 7))
        return self.audio


def verilog_lines():
    return ["localparam signed [17:0] %s = 18'sd%d;" % (k, v) if v >= 0 else
            "localparam signed [17:0] %s = -18'sd%d;" % (k, -v) for k, v in C.items()]


def table_lines():
    """The coefficient table: case items of {cfg[3:0], idx[4:0]}; zero entries fall to the default."""
    out = []
    for cfg in range(16):
        for i, v in enumerate(TAB[cfg]):
            if v:
                out.append("            9'd%d: cf = %s18'sd%d;   // %s %s" % (
                    cfg * 32 + i, "-" if v < 0 else " ", abs(v), BOARDS[cfg >> 2] + "_%d" % (cfg & 3), KEYS[i]))
    return out


def check(paths):
    bad = n = 0
    want = dict(C, **CHECK_EXTRA)
    seen = set()
    tab = "\n".join(table_lines())
    tabs = 0
    for p in paths:
        txt = open(p).read()
        for k, v in want.items():
            for mt in re.finditer(r"\b%s\s*=\s*(-?)\s*(?:\d+'sd)?(\d+)\s*;" % k, txt):
                n += 1; seen.add(k)
                got = int(mt.group(2)) * (-1 if mt.group(1) else 1)
                if got != v:
                    print("%s: %s = %d, expected %d" % (p, k, got, v))
                    bad += 1
        mt = re.search(r"// BEGIN gx_mix_coefs table\n(.*?)\n\s*// END gx_mix_coefs table", txt, re.S)
        if mt:
            tabs += 1
            if mt.group(1).rstrip() != tab.rstrip():
                print("%s: coefficient table differs from gx_mix_coefs.py --table output" % p)
                bad += 1
    miss = set(C) - seen
    if miss:
        print("gx_mix_coefs: not found: %s" % " ".join(sorted(miss)))
        bad += 1
    if tabs != 1:
        print("gx_mix_coefs: %d coefficient tables found, expected 1" % tabs)
        bad += 1
    print("gx_mix_coefs: %d localparams and %d table entries checked, %s" % (
        n, len(tab.splitlines()) * tabs, "all match" if bad == 0 else "%d mismatches" % bad))
    return bad


def response_table():
    """Per board and source: |model| (the discrete step-mean map) vs the continuous network, dB, VOL off."""
    import cmath
    for board in range(4):
        s = discretise(board, 0, 0)
        print("%s  Rth %.0f ohm  C20 %.3g uF" % (BOARDS[board], RTH[board], C20[board] * 1e6))
        for j, n in enumerate(SRC):
            row = []
            for f in (100, 200, 500, 1000, 3000, 6000):
                z = cmath.exp(2j * math.pi * f * T)
                # discrete: x' = Phi x + Gam u, ym = Cm x + Dm u, u held: H(z) = Cm (zI - Phi)^-1 Gam z^0 ... (x then u)
                zi = [[z - s["phi"][0][0], -s["phi"][0][1]], [-s["phi"][1][0], z - s["phi"][1][1]]]
                det = zi[0][0] * zi[1][1] - zi[0][1] * zi[1][0]
                inv = [[zi[1][1] / det, -zi[0][1] / det], [-zi[1][0] / det, zi[0][0] / det]]
                g = [s["gam"][0][j], s["gam"][1][j]]
                xr = [inv[0][0] * g[0] + inv[0][1] * g[1], inv[1][0] * g[0] + inv[1][1] * g[1]]
                hd = s["cm"][0][0] * xr[0] + s["cm"][0][1] * xr[1] + s["dm"][0][j]
                w = 2j * math.pi * f
                si = [[w - s["a"][0][0], -s["a"][0][1]], [-s["a"][1][0], w - s["a"][1][1]]]
                det = si[0][0] * si[1][1] - si[0][1] * si[1][0]
                inv = [[si[1][1] / det, -si[0][1] / det], [-si[1][0] / det, si[0][0] / det]]
                g = [s["b"][0][j], s["b"][1][j]]
                xr = [inv[0][0] * g[0] + inv[0][1] * g[1], inv[1][0] * g[0] + inv[1][1] * g[1]]
                hc = s["c"][0][0] * xr[0] + s["c"][0][1] * xr[1] + s["d"][0][j]
                row.append("%6.2f/%6.2f" % (20 * math.log10(abs(hd) + 1e-30), 20 * math.log10(abs(hc) + 1e-30)))
            print("  %s  %s" % (n, "  ".join(row)))


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--check':
        sys.exit(1 if check(sys.argv[2:]) else 0)
    if len(sys.argv) > 1 and sys.argv[1] == '--table':
        response_table()
        sys.exit(0)
    for line in verilog_lines():
        print(line)
    print("            // BEGIN gx_mix_coefs table")
    for line in table_lines():
        print(line)
    print("            // END gx_mix_coefs table")
