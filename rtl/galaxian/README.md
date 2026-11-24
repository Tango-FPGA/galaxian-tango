# rtl/galaxian -- vendored upstream files

Source: <https://github.com/MiSTer-devel/Arcade-Galaxian_MiSTer>, commit
`e6b4dc5e7a89b2f9aceeed338eab71ea9b5624aa` ("Move clone to alternatives (#66)").

The T80 files are byte-identical to that commit (`rtl/T80/` there). They are never edited here: a change the Tango
port needs goes into a build-time copy or a replacement file, listed in `NOTICE` with the reason.

`hiscore.v` is upstream's `rtl/hiscore.v` (Hiscores_MiSTer version 0014) with the Tango changes T1-T5, which its
header lists after the version history. The changes were made first in galaga-tango's copy of the module, and this
file was copied from that copy byte for byte (CRLF line endings, tabs). The parameters are upstream's; T4 adds one
input port, `vblank`. Licences: `NOTICE`.

| File | sha256 |
|---|---|
| `hiscore.v` | `488060e5bcdb26238555562f3aa40fb4818fdda114a2b2088b8d15d8cf0789a8` (upstream's: `668f30e0...`) |
| `T80/T80_Pack.vhd` | `90d5ea223629b169b25167de9ce2940b29a72cce24ede4a001a508d70ed7b193` |
| `T80/T80_ALU.vhd` | `823a062b8be873505ac16e627351a5105101243a11483bf8f2446214893b739e` |
| `T80/T80_MCode.vhd` | `0e24fa45984d9a51a8dc7b2608fa6d616c8a52accbad0524a4852f9c78230ed8` |
| `T80/T80_Reg.vhd` | `b40f92eb96fc55fa0adc8ca1bbb20d99133ae1dfe3728b146e37ee00ef588783` |
| `T80/T80.vhd` | `9677900c2c28f3ab2404a1c8f039e3421246f78647b3936c841b1d8c43059ebe` |
| `T80/T80se.vhd` | `d528be5e4a75a8e45d1965740bcd6c77180bd54e1862b8e177bea8a432e58588` |

The upstream core instantiates `T80se` twice: the main CPU (`galaxian.vhd`) and King and Balloon's speech CPU
(`kb_synth.vhd`). Compile order: `T80_Pack`, `T80_ALU`, `T80_MCode`, `T80_Reg`, `T80`, `T80se` (`T80`, `T80_MCode`
and `T80se` use `work.T80_Pack`).

Upstream's `hiscore.v` has LF line endings (sha256 `668f30e01f0062e1fc120c9b1d6f7228dd428ede5943c2ff649ebfcb3364e697`;
the same text with CRLF, as galaga-tango kept it before the fix, is `856b392d...`).

Not vendored: the game-logic VHDL, which the Tango authors rewrite from the schematics (`NOTICE`), `pause.v`, the
T80 variants the core does not instantiate, and the RAM, PLL and TTL helpers.
