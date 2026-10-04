10-Yard Fight (Irem M58) for MiSTer
===================================

**Status: playable.** Background, sprites, score panel and sound are all
working and verified on real MiSTer hardware. All six ROM sets have MRAs.
Flip screen (the 180 degree cocktail rotation) works and is verified on
hardware too.

An FPGA implementation of the Irem M58 arcade board, which ran 10-Yard Fight
(1983) and its variants.

Credits and provenance
----------------------

This core is derived from the MiSTer **Irem M62** core, whose sources were
copied into this repository as its starting point:

- Original PACE framework by **Mark McDougall (tcdev)**
- Irem M62 implementation enhanced by **Gyorgy Szombathelyi**
- Published as [MiSTer-devel/Arcade-IremM62_MiSTer](https://github.com/MiSTer-devel/Arcade-IremM62_MiSTer),
  imported here at commit `8324124` (2025-12-09)

Licensing follows upstream. The M62 core is distributed under the GPL, as is
the MiSTer `sys` framework it includes; this work inherits those terms.

Why the M62 core is the base
----------------------------

M58 is not an M62 board, but the two are architecturally close — closer than
the board numbers suggest. Compared against Kung-Fu Master, the M62 game that
most resembles it:

| | M58 (10-Yard Fight) | M62 (Kung-Fu Master) |
|---|---|---|
| Main CPU | Z80 @ 18.432 MHz / 6 | identical |
| Pixel clock | 18.432 MHz / 3 = 6.144 MHz | identical |
| Raster | 384 x 282, 256x224 visible | 384 x 284, 256x256 visible |
| Tile RAM | 0x8000-0x8FFF (4K) | 0xD000-0xDFFF (4K) |
| Tilemap | 64x32, 8x8, 3bpp, two-half column mapping | same structure |
| Sprite RAM | 0xC820-0xC87F (96 bytes, 24 sprites) | 0xC000-0xC0FF (64 sprites) |
| Work RAM | 0xE000-0xEFFF | identical |
| Inputs/DIPs | memory-mapped 0xD000-0xD004 | Z80 I/O ports 0x00-0x04 |
| Sound board | 6803 + 2x AY-3-8910 + 2x MSM5205 | same chips, different ADPCM decode |

MAME's own `m58.cpp` notes that the driver is "loosely based on the Kung Fu
Master driver."

M58 support was first built as a thirteenth hardware variant inside the M62
core's per-game `hwsel` switch. Once it worked, the twelve M62 games were
removed - they have their own core upstream - leaving only the M58 paths:
no `hwsel`, no bank switching or protection, no screen rotation, and no
second tile ROM.

Work remaining
--------------

- [x] Import M62 sources, verify a clean Quartus build
- [x] Rename project, add `HW_10YARD` variant constant
- [x] Memory map: memory-mapped I/O in place of Z80 port I/O
- [x] PLL retune to 24.576MHz: exact 6.144MHz pixel clock, 3.072MHz Z80
- [x] Video timing: 282 lines, 224 visible
- [x] Tilemap addressing for M58 VRAM layout
- [x] Palette: six PROMs, M58 resistor-network weighting
- [x] Sprite engine: 24-entry list, 16x32 pairs, two-stage colour lookup
- [x] Scroll-panel bitmap layer (the status/yardage strip)
- [x] Sound board: dual MSM5205 with M52-style ADPCM decode
- [x] MRA for the World parent set
- [x] Hardware testing on DE10-Nano
- [x] MRAs for the other five ROM sets
- [x] Flip screen / cocktail, with the score panel's flipped window taken
      from the board rather than from MAME (see docs/hardware-notes.md)
- [x] Remove the twelve M62 games and their variant logic
- [ ] High score saving (MRAs done, awaiting a hardware test)
- [ ] The board's LM358 ADPCM low-pass, which MAME omits (OSD "Audio
      filter", built, awaiting a hardware listen; see docs/hardware-notes.md)

Supported ROM sets (target)
---------------------------

All six sets in MAME's `m58.cpp`, all the same game:

- `10yard` — 10-Yard Fight (World, set 1)
- `10yardj` — 10-Yard Fight (Japan)
- `vs10yard` / `vs10yardj` / `vs10yardu` — Vs 10-Yard Fight
- `10yard85` — 10-Yard Fight '85 (US, Taito license)

Note these are Irem M58 arcade sets, not the Nintendo VS. System.

Accuracy
--------

`docs/hardware-notes.md` records what has been verified against Irem's own
schematics rather than against MAME: the raster presets (384x282), the colour
resistor ladders, the sprite pulldowns, the 18.432MHz crystal, sprite
priority, the ADPCM mixing, and the 74LS86 gates that invert every H and V
counter bit ahead of the scroll adders when the screen is flipped, and the
74LS85 comparator that sets the score panel's window. That comparator makes
the flipped panel 64 pixels wide with its content 8 pixels in from the edge,
which is what the board does and not what MAME draws. The notes also record
what remains unverified and would need a real board. `tools/verify_palette.py` proves every palette entry
matches MAME's computed palette exactly.

ROMs
----

ROMs are not included. You must provide your own, matching the checksums in
the supplied `.mra` files. See
<https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms>.
