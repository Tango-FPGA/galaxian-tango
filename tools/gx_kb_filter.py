#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
# gx_kb_filter.py -- King & Balloon speech-board output filter (KB p15, drawing 02-70103): the analog transfer
# function by nodal analysis, its 48 kHz discretisation, the fixed-point coefficients of rtl/gx/gx_kb_filter.v and a
# bit-exact model of that RTL.  numpy only.
#
#   tools/gx_kb_filter.py                       coefficients, Verilog localparams, response table, headroom
#   tools/gx_kb_filter.py model <in> <out>      bit-exact RTL model: one Q5.11 input sample per line (decimal) ->
#                                               one Q5.11 output sample per line
#   tools/gx_kb_filter.py step <n> <volts>      analog step response of amplitude <volts>, n samples at 48 kHz
#                                               (t = k/fs, k = 0..n-1), one value in volts per line
#   tools/gx_kb_filter.py gain <hz>             |H| analog, digital (float), digital (quantised coefficients)
#
# Circuit (KB p15).  IC15 TL081 follower buffers the R-2R ladder.  Then:
#   Vi --R28-- X --R29-- Y --R30-- P ;  C11 X->gnd ;  C12 Y->V1 ;  C13 P->gnd ;  V1 = P (IC16a follower)
#   V1 --R31-- U --R32-- Q ;  C16 U->V2 ;  C17 Q->gnd ;  V2 = Q (IC16b follower) ; V2 --R33 47K--> OUT
# R28/C11 is loaded by R29 (not buffered), so stage 1 is one third-order section.  IC16a's output drives stage 2,
# which is the textbook unity-gain Sallen-Key.  Nodal equations of stage 1 (G = 1/R):
#   X: (X - Vi) G28 + X s C11 + (X - Y) G29 = 0
#   Y: (Y - X) G29 + (Y - P) s C12 + (Y - P) G30 = 0
#   P: (P - Y) G30 + P s C13 = 0
# P gives Y = P (1 + s R30 C13); Y gives X = P [1 + s (R29 + R30) C13 + s^2 R29 R30 C12 C13]; X gives
#   Vi / V1 = [1 + s (R29 + R30) C13 + s^2 R29 R30 C12 C13] (1 + R28/R29 + s R28 C11) - (R28/R29)(1 + s R30 C13)
# Stage 2: V1 / V2 = 1 + s C17 (R31 + R32) + s^2 R31 R32 C16 C17.  Both are 1 at s = 0 (unity DC gain).
#
# Discretisation: bilinear transform per section, each prewarped at its own pole magnitude |p| (the real pole's
# corner, each pair's natural frequency), DC gain 1 per section.  Bilinear maps the whole jw axis onto the unit
# circle, so nothing aliases; prewarping puts each section's corner / resonance at the right frequency, and the
# remaining error is the frequency compression towards Nyquist, which only adds attenuation where the analog filter
# is already below -45 dB.  Matched-z (and impulse invariance) keep the poles but have no zeros at z = -1: the
# response flattens towards Nyquist (aliasing).  The table printed below compares all three.
#
# Fixed point (gx_kb_filter.v): one real section then two biquads in Direct Form I, signals Q6.18 in 24 bits,
# coefficients Q2.16 in 18 bits, one shared multiplier.  For a section with denominator 1 + a1 z^-1 + a2 z^-2
# (a2 = 0 for the real pole) and k = 1 + a1 + a2 (all three as Q2.16 integers, k computed from the rounded a1/a2
# so the DC gain is exactly 1):
#   real:   acc = k * 2 (x[n] + x[n-1])          - a1 * 4 y[n-1]
#   biquad: acc = k * (x[n] + 2 x[n-1] + x[n-2]) - a1 * 4 y[n-1] - a2 * 4 y[n-2]
#   y[n] = sat24((acc + 2^17) >> 18)
# Input: Q5.11 << 7.  Output: sat16((y + 64) >> 7), Q5.11 (+/-16 V: the resonant peaks of real speech data reach
# +9.13 V, past a Q4.12 range; the op-amps run from +/-12 V).
import sys
import numpy as np

FS = 24.576e6 / 512          # ce_48k, exactly 48 kHz
R28 = R29 = R30 = 2.2e3
C11, C12, C13 = 0.033e-6, 0.068e-6, 0.0033e-6
R31 = R32 = 3.3e3
C16, C17 = 0.1e-6, 0.0033e-6

P = np.polynomial.polynomial   # coefficient arrays in ascending powers of s


def analog_den():
    """D(s) = Vi/V2 as an ascending-power coefficient array (H = 1/D)."""
    a = np.array([1.0, (R29 + R30) * C13, R29 * R30 * C12 * C13])
    b = np.array([1.0 + R28 / R29, R28 * C11])
    d1 = P.polysub(P.polymul(a, b), np.array([R28 / R29, R28 / R29 * R30 * C13]))
    d2 = np.array([1.0, C17 * (R31 + R32), R31 * R32 * C16 * C17])
    return d1, d2, P.polymul(d1, d2)


def analog_nodal(f):
    """H(j 2 pi f) by solving the complex nodal matrix of the full circuit directly (cross-check of analog_den)."""
    s = 2j * np.pi * f
    # unknowns X, Y, P(=V1), U, Q(=V2); Vi = 1
    g28, g29, g30, g31, g32 = 1 / R28, 1 / R29, 1 / R30, 1 / R31, 1 / R32
    m = np.zeros((5, 5), complex)
    r = np.zeros(5, complex)
    m[0, 0] = g28 + s * C11 + g29; m[0, 1] = -g29; r[0] = g28
    m[1, 0] = -g29; m[1, 1] = g29 + s * C12 + g30; m[1, 2] = -(s * C12 + g30)
    m[2, 1] = -g30; m[2, 2] = g30 + s * C13
    m[3, 2] = -g31; m[3, 3] = g31 + s * C16 + g32; m[3, 4] = -(s * C16 + g32)
    m[4, 3] = -g32; m[4, 4] = g32 + s * C17
    return np.linalg.solve(m, r)[4]


def h_analog(f):
    _, _, d = analog_den()
    return 1.0 / P.polyval(2j * np.pi * f, d)


def sections():
    """Analog poles grouped as [real] + [pairs sorted by Q]: list of (kind, w0, Q)."""
    _, _, d = analog_den()
    roots = P.polyroots(d)
    real = [r.real for r in roots if abs(r.imag) < 1e-6 * abs(r)]
    pairs = [r for r in roots if r.imag > 1e-6 * abs(r)]
    assert len(real) == 1 and len(pairs) == 2, roots
    out = [("real", -real[0], None)]
    for p in sorted(pairs, key=lambda p: abs(p) / (-2 * p.real)):
        w0 = abs(p)
        out.append(("pair", w0, w0 / (-2 * p.real)))
    return out


def bilinear(kind, w0, q, prewarp=True):
    """Digital denominator [1, a1, a2] of a unity-DC section; numerator is k (1 + z^-1)^n / 2^n."""
    T = 1 / FS
    c = w0 / np.tan(w0 * T / 2) if prewarp else 2 / T
    if kind == "real":                       # w0 / (s + w0)
        a0 = c + w0; a1 = (w0 - c) / a0
        return [1.0, a1, 0.0]
    a0 = c * c + w0 / q * c + w0 * w0        # w0^2 / (s^2 + (w0/q) s + w0^2)
    a1 = 2 * (w0 * w0 - c * c) / a0
    a2 = (c * c - w0 / q * c + w0 * w0) / a0
    return [1.0, a1, a2]


def h_bilinear_sections(den, f):
    z1 = np.exp(-2j * np.pi * f / FS)
    h = 1.0
    for kind, (_, a1, a2) in den:
        n = 1 if kind == "real" else 2
        k = 1 + a1 + a2
        h *= k * ((1 + z1) / 2) ** n / (1 + a1 * z1 + a2 * z1 * z1)
    return h


def h_matched(f):
    _, _, d = analog_den()
    z1 = np.exp(-2j * np.pi * f / FS)
    h = 1.0
    for r in P.polyroots(d):
        zp = np.exp(r / FS)
        h *= (1 - zp) / (1 - zp * z1)
    return h


def quantise():
    """[(kind, k, a1, a2)] as Q2.16 integers, k = 2^16 + a1 + a2."""
    q = []
    for kind, w0, qq in sections():
        _, a1, a2 = bilinear(kind, w0, qq)
        a1q, a2q = int(round(a1 * 65536)), int(round(a2 * 65536))
        q.append((kind, 65536 + a1q + a2q, a1q, a2q))
    return q


def h_quant(f):
    return h_bilinear_sections([(k, [1.0, a1 / 65536, a2 / 65536]) for k, _, a1, a2 in quantise()], f)


def h_float(f):
    return h_bilinear_sections([(kind, bilinear(kind, w0, q)) for kind, w0, q in sections()], f)


def h_plain_bilinear(f):
    return h_bilinear_sections([(kind, bilinear(kind, w0, q, prewarp=False)) for kind, w0, q in sections()], f)


def sat(v, bits):
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    return lo if v < lo else hi if v > hi else v


def model(xs):
    """Bit-exact model of gx_kb_filter.v: Q5.11 ints in, Q5.11 ints out (output after each input sample)."""
    co = quantise()
    xh = [0, 0]                  # x[n-1] of the real section (input history)
    yh = [[0, 0] for _ in co]    # y[n-1], y[n-2] per section
    out = []
    for x in xs:
        x0 = sat(int(x), 16) << 7
        v = x0
        new = []
        for i, (kind, k, a1, a2) in enumerate(co):
            if kind == "real":
                acc = k * (2 * (v + xh[0])) - a1 * (4 * yh[i][0])
            else:
                vin = (x0, xh[0], xh[1]) if i == 0 else (new[i - 1], yh[i - 1][0], yh[i - 1][1])
                acc = k * (vin[0] + 2 * vin[1] + vin[2]) - a1 * (4 * yh[i][0]) - a2 * (4 * yh[i][1])
            y = sat((acc + (1 << 17)) >> 18, 24)
            new.append(y)
            v = y
        xh = [x0, xh[0]]
        for i in range(len(co)):
            yh[i] = [new[i], yh[i][0]]
        out.append(sat((new[-1] + 64) >> 7, 16))
    return out


def analog_step(n, amp):
    """Exact analog step response at t = k/FS from the residues of H(s)/s (distinct poles)."""
    _, _, d = analog_den()
    dd = P.polyder(d)
    roots = P.polyroots(d)
    t = np.arange(n) / FS
    y = np.ones(n, complex)
    for p in roots:
        y += np.exp(p * t) / (p * P.polyval(p, dd))
    return amp * y.real


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "model":
        xs = [int(l) for l in open(sys.argv[2]) if l.strip()]
        with open(sys.argv[3], "w") as fo:
            fo.write("".join("%d\n" % y for y in model(xs)))
        return
    if len(sys.argv) > 1 and sys.argv[1] == "step":
        for v in analog_step(int(sys.argv[2]), float(sys.argv[3])):
            print("%.9f" % v)
        return
    if len(sys.argv) > 1 and sys.argv[1] == "gain":
        f = float(sys.argv[2])
        print("%.9f %.9f %.9f" % (abs(h_analog(f)), abs(h_float(f)), abs(h_quant(f))))
        return

    d1, d2, d = analog_den()
    print("Analog, Vi/V2 = D(s), ascending powers of s:")
    print("  stage 1 (R28/C11 + SK1, 3rd order):", " ".join("%.6e" % c for c in d1))
    print("  stage 2 (SK2, 2nd order):          ", " ".join("%.6e" % c for c in d2))
    for f in (100, 1e3, 3e3, 1e4):
        a, b = h_analog(f), analog_nodal(f)
        assert abs(a - b) < 1e-9 * max(1, abs(b)), (f, a, b)
    print("  polynomial H(jw) = direct nodal solve at 100 Hz, 1, 3, 10 kHz (|diff| < 1e-9): ok")
    print("Poles:")
    for kind, w0, q in sections():
        if kind == "real":
            print("  real pole  f = %8.2f Hz" % (w0 / 2 / np.pi))
        else:
            print("  pole pair  f0 = %8.2f Hz  Q = %.4f" % (w0 / 2 / np.pi, q))
    print("  (an isolated SK1 would be f0 %.0f Hz Q %.2f; SK2 f0 %.0f Hz Q %.2f)" % (
        1 / (2 * np.pi * np.sqrt(R29 * R30 * C12 * C13)), np.sqrt(R29 * R30 * C12 * C13) / ((R29 + R30) * C13),
        1 / (2 * np.pi * np.sqrt(R31 * R32 * C16 * C17)), np.sqrt(R31 * R32 * C16 * C17) / ((R31 + R32) * C17)))

    co = quantise()
    print("Digital (fs = 48 kHz), per-section bilinear prewarped at |p|; Q2.16 integers, k = 65536 + a1 + a2:")
    for i, (kind, k, a1, a2) in enumerate(co):
        print("  section %d %-6s k = %6d  a1 = %7d  a2 = %6d   (a1 = %.8f a2 = %.8f)" % (
            i, kind, k, a1, a2, a1 / 65536, a2 / 65536))
    print("Verilog localparams:")
    for i, (kind, k, a1, a2) in enumerate(co):
        print("    localparam signed [17:0] K%d = %d, NA1_%d = %d, NA2_%d = %d;" % (i, k, i, -a1, i, -a2))

    print("Magnitude response (dB):")
    print("   f (Hz)    analog  dig-float   dig-Q2.16  |  plain-bilinear  matched-z")
    for f in (100, 1000, 2000, 3000, 5000, 10000, 20000):
        db = lambda h: 20 * np.log10(abs(h))
        print("  %7.0f  %8.3f  %9.3f  %10.3f  |  %14.3f  %9.3f" % (
            f, db(h_analog(f)), db(h_float(f)), db(h_quant(f)), db(h_plain_bilinear(f)), db(h_matched(f))))
    for fmax in (3000, 4000, 5000):
        fr = np.linspace(20, fmax, 1000)
        for name, fn in (("dig-Q2.16", h_quant), ("plain-bilinear", h_plain_bilinear), ("matched-z", h_matched)):
            e = max(abs(20 * np.log10(abs(fn(f)) / abs(h_analog(f)))) for f in fr)
            print("  max |dB error| 20 Hz..%d kHz vs analog: %-15s %.3f dB" % (fmax // 1000, name, e))
    fr = np.linspace(20, 5000, 2000)
    fp = fr[np.argmax([abs(h_analog(f)) for f in fr])]
    print("  analog peak: %.3f dB at %.0f Hz" % (20 * np.log10(abs(h_analog(fp))), fp))

    imp = model([2048] + [0] * 4095)       # 1 V impulse; output in Q5.11
    l1 = sum(abs(v) for v in imp) / 2048.0
    st = model([2048] * 4096)
    print("Headroom: L1 norm of the impulse response %.4f; input 0..4.6875 V (codes 00..F0) -> worst-case output "
          "%.3f .. %.3f V (Q5.11 range -16 .. +16)" % (l1, 2.34375 - 2.34375 * l1, 2.34375 + 2.34375 * l1))
    print("  1 V step: peak %.4f V (overshoot %.1f %%); a full-scale 0 -> 4.6875 V step peaks at %.3f V" % (
        max(st) / 2048, (max(st) / 2048 - 1) * 100, 4.6875 * max(st) / 2048))


if __name__ == "__main__":
    main()
