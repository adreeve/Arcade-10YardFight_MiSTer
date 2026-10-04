Hardware notes
==============

Findings taken from Irem's own service manual for 10-Yard Fight
(72-00049-001), which contains the board schematics. The PDF itself is not
committed — it lives in `ref/` (gitignored). Pages below refer to that file.

Schematic index
---------------

| Pages | Content |
|---|---|
| 26-28 | Power supply board and schematic, filter board |
| 30    | **TOP PCB (M52-Sound G)** — the sound board |
| 32-35 | CENTER PCB (M58-A-A), sheets 1-4 |
| 37-41 | BOTTOM PCB (M58-B-A), sheets 1-5 |
| 42-45 | Cabinet wiring diagrams |

What the schematics confirm
---------------------------

**The sound board is the M52 one.** Irem labels it "M52-Sound G" on the
schematic (page 30). The core decodes audio as MAME's `IREM_M52_LARGE_AUDIO`
variant, and this is direct confirmation that the board family is right
rather than inferred from MAME's device choice.

**The colour DACs use the resistor values MAME assumes.** On BOTTOM PCB sheet
5 of 5 (page 41), the palette PROMs (24S10) drive resistor ladders:

    R13 = 1K   R12 = 220  R14 = 470     3-resistor ladder
    R23 = 1K   R24 = 470  R25 = 220     3-resistor ladder
    R15 = 470  R16 = 220                2-resistor ladder

matching the 1000/470/220 and 470/220 networks in `m58_state::palette()`.
The ladders run to CN1's RED, GREEN and BLUE pins. So the ladder tables in
`platform.vhd`, which `tools/verify_palette.py` proves equal to MAME's
computed palette, rest on resistor values that the real board actually uses.

**The sprite DAC matches MAME, pulldown included.** BOTTOM PCB sheet 4 of 5
(page 40) carries the sprite palette PROM, an 18SC30 (32x8 - the 16-entry
palette, dumped as yard.1f), driving:

    R10 = 1K   R9 = 470  R8 = 220     -> BLUE   (CN1 23A)
    R7  = 1K   R6 = 470  R5 = 220     -> GREEN  (CN1 24A)
    R4  = 470  R3 = 220               -> RED    (CN1 24B)

with a 470 ohm resistor to ground on each output line (R11 blue, R1 green,
R2 red). That is exactly MAME's second weights call, which passes pulldown
470 for each sprite network and is why sprites are dimmer than the
background. Both the ladder values and the pulldown are confirmed.

Audio: what the sound board sheet shows
---------------------------------------

TOP PCB (M52-Sound G), page 30: 6803 at 3F with a 3.579545MHz crystal, two
AY-3-8910s (3H, 3J/3K), two MSM5205s (3L, 3M) with a 384kHz crystal, and an
LM358 (3N) analog stage feeding VR1, a 50K volume pot.

**The two ADPCM channels are mixed equally.** 3L and 3M each reach the mixer
through a 10K resistor (R19, R20). The scan is too degraded to read R19
confidently - at full magnification the middle glyph could be 0 or C - but
MAME's discrete model for this board defines M52_R19 as RES_K(10), matching
R20. So the core's equal sum of the two ADPCM outputs is right, and no
change is warranted. Worth recording as a case where the scan could not
settle a value and a second source did.

**The board low-passes the ADPCM, not the AYs; MAME does neither.** MAME
models the M62 board with a netlist and the M52 SoundC board with a discrete
filter, but gives M52-large - the variant this game uses - neither: all four
sources are routed flat at 0.80 gain.

Read from the greyscale scan (`jp2_crop.py 30 450 1500 1400 2300`, rotated
90 degrees), the circuit is:

- R19/R20 sum the two MSM5205 outputs, coupled through C37 to 3N-A pin 3,
  biased by R21 3.3K / R23 2.2K / R22 47K. 3N-A is a unity follower.
- R12 10K into C30 0.022u to ground, then a unity-gain Sallen-Key on 3N-B:
  R13 10K, R14 10K, C32 0.027u from the R13/R14 node to the output, C36
  0.0068u from pin 5 to ground. Pin 6 is tied to pin 7.
- The filtered output reaches VR1 through R15; the AYs join there through
  R25 and are not filtered.

That is a third-order low-pass, -3dB at 620Hz, -20dB at 2kHz, -37dB at 4kHz.
The speech and crowd samples come out much duller than the flat mix.

An earlier reading of the 1-bit PDF gave C30 0.0022u, C32 0.0027u, C36
0.00068u - a factor of ten low, and the source of a "corner around 10kHz"
estimate here. The greyscale scan is unambiguous, and agrees with MAME's
SoundC defines (C30 0.022u, C38 0.0068u) except that MAME has C32 0.022u
where this board has 0.027u. MAME's SoundC graph also stops at the R12/C30
RC and mixes that node, leaving its Sallen-Key output unused; the board
mixes the Sallen-Key output.

The core models it behind the OSD option "Audio filter" (Sound_Board.vhd):
a forward Euler simulation of the three capacitor voltages at clock_E, which
matches the analog response to 0.1dB from 100Hz to 4kHz. The mix levels are
left as they were. R15 was the open question there - MAME's source says the
schematic has 22K "althought 10-Yard states 2.2". A photo of a real sound
board (2026-10-03) shows R15 banded red-red-red: 2.2K, agreeing with MAME's
note rather than the drawing. Photo colour is not a measurement - a red
third band and an orange one are easy to confuse under a camera's white
balance - but two independent sources now say 2.2K.

A closer look at that photo (`D:\Work\MiSTer\screenshots\sound pcb.png`,
analog corner of the M52-SOUND-G board) compares each resistor with its
neighbours rather than reading colours absolutely:

- R15 shows three red bands and looks nothing like R13 and R14 beside it,
  which share one pattern (pale, pale, orange - brown-black-orange, 10K, as
  the schematic says). 2.2K for R15 is now well supported.
- R19 and R20 look identical to each other and match R13/R14's pattern, so
  the two ADPCM channels are mixed equally through 10K, as assumed.
- R25 shows the same pattern: consistent with 10K.
- C37, the large yellow box capacitor, is marked "104K": 0.1uF, matching the
  schematic.
- The filter capacitors C30, C32 and C36 are small brown discs whose codes
  are not legible at this resolution, and the copper traces are not visible,
  so neither the cutoff values nor the AY-after-filter routing are confirmed
  by the photo.

A photo of the solder side (`sound pcb back.png`, 675x1180) does not settle
the routing either: the probable LM358 footprint is visible in the analog
corner, but at about 11 pixels per 0.1" pin pitch the traces cannot be
followed reliably, and on a two-sided board part of any path runs on the
component side, hidden under the parts.

A 2.2K R15 against a 10K R25 weights the filtered ADPCM about 4.5x (13dB)
above the AYs at VR1, relative to equal resistors. That does not translate
directly into a core gain: the core's AY/ADPCM balance follows MAME's flat
0.80 routing, and the two sources' own output swings (the MSM5205 DAC through
R19/R20, the AY outputs before R25) are not known in the same units. The
mix is left as it is. The filter cuts the samples' high end, so if they
sound too quiet against the music with it on, this is the reason to raise
them.

On hardware, with the filter on, they did sound too quiet (2026-10-03). The
core now has an OSD "Sample level" (1x, 1.5x, 2x, 3x) scaling the ADPCM sum
before the mix, to be set by ear. The mixer also now clamps to its 13-bit
range: before, a loud AY passage over a loud sample wrapped around, which a
gain would have made common.

Possible inaccuracy inherited from MAME
---------------------------------------

The 470 ohm pulldowns sit on the shared CN1 RGB lines, which the
character/radar DAC on sheet 5 also drives. MAME computes the character and
radar palettes with no pulldown at all. If those resistors load the line
regardless of which DAC drives it, real character colours are dimmer than
MAME renders them, and this core reproduces MAME's version exactly.

Whether that is an error depends on whether the character PROM outputs go
high-Z when sprites take priority; CN1 pins 22B and 27A carry PRIORITY
signals, so some arbitration exists. Settling it needs measurement on a real
board. Recorded here rather than acted on: changing it would make the core
disagree with MAME without proof that the hardware agrees.

**The master clock is 18.432MHz.** BOTTOM PCB sheet 1 of 5 (page 37) shows
X1 = 18.432MHz in an inverter oscillator (R17 100, R18 1K, R22 330, C1 390pF,
100pF). That is the figure the PLL retune targets: 24.576MHz system clock,
6.144MHz pixel clock, 3.072MHz Z80. Confirmed against hardware, not just
MAME.

**The 282-line frame is confirmed at the gate level.** The vertical counter
presets to 0xE6 and runs to 0x1FF, giving 512 - 230 = 282 lines, which is
exactly the core's `vcnt <= '0'&x"E6"`. Read from the load inputs on sheet 1:

    6H ('161)  D tied low, C/B/A pulled high   -> V256 V128 V64 V32 = 0 1 1 1
    6F ('161)  D/C tied low, B/A pulled high   -> V16  V8   V4  V2  = 0 0 1 1
    6J ('74)                                   -> V1              = 0

**The 384-pixel line is confirmed the same way.** The horizontal counter
presets to 0x080 and runs to 0x1FF, giving 384 pixels, exactly the core's
hcnt range:

    6M ('161)  D/B/A tied low, C pulled high   -> H256 H128 H64 H32 = 0 1 0 0
    6L ('161)  all four tied low               -> H16  H8   H4  H2  = 0 0 0 0
    6J ('74)                                   -> H1              = 0

The 6L reading is unambiguous - all four load inputs sit on the ground bus.
6M is read from which pins join that bus, with C instead running up to a
pull-up; it gives 0x080, which the 384-pixel line corroborates.

Together: the raster is 384 x 282 at the gate level. This is the parameter
MAME had wrong for this game between 0.122u8 and 0.229 (bug 06650), so
having it from the schematic rather than from MAME is worth something.

Reading it needed the Internet Archive's _jp2.zip scans: the PDF in the same
item is 1-bit thresholded, which destroys the thin strokes distinguishing a
ground symbol from a pull-up. The JP2s are 8-bit greyscale at the same
resolution. `tools/jp2_crop.py` crops them.

**The vertical counter is 9 bits.** The same sheet carries '161 counters at
6H, 6F and 6M with a '74 at 6J, tapping V1, V2, V4 ... V256. That matches the
core's 9-bit vcnt preset to span 282 lines, and is consistent with the M62
core's note that its 282-line figure came from M52 schematics. The preset
values themselves were traced from the load inputs - see the 282-line and
384-pixel entries above.

**Sprite priority is sprite-opaque-wins, with no tiles-over-sprites path.**
BOTTOM PCB sheet 4 shows the sprite palette PROM (18SC30) fed from a '174 at
1H, with a gate at 2C watching the sprite pixel's colour bits and driving,
through 1C and an LS38, the PRIORITY pin on CN1 (22B). The B board tells the
A board that a sprite pixel is present; there is no path giving tiles
priority over sprites.

That matters because the M62 core this is built on carries a comment
admitting its Kung-Fu Master priority is a guess ("as a hack, giving tiles
priority over sprites for the first ~106 lines"). The M58 path never set
prio, so it stays '0' - which the schematic confirms is right for M58, not
merely convenient. With the M62 games removed, the tilemap now drives prio
to '0' outright.

Next to the PROM is jumper J1, matching the option the M62 core documents:
"J1: selects whether bit 4 of obj color code selects or not high priority
over tiles." Its fitted position on this board was not read.

The existence of explicit priority arbitration also bears on the pulldown
question above: if the PRIORITY signal gates which DAC drives the shared RGB
lines, the 470 ohm pulldowns may load only the active one, which would make
MAME's asymmetric treatment defensible. Still needs a real board to settle.

Screen flip: the counters are inverted, then scrolled
-----------------------------------------------------

**Confirmed on BOTTOM PCB sheet 1 of 5 (page 37).** Every horizontal and
vertical counter bit passes through a 74LS86 XOR gate before it leaves the
board:

| Bits | XOR package | Output goes to |
|---|---|---|
| H1..H128 | 7L and 7M (marked `86`) | RM1 (1K) then CN2 21A-24B, labelled H1E, H2, H4 ... H128 |
| V1..V128 | 7F and 7H (marked `86`) | RM2 then CN2, labelled V1E, V2, V4 ... V128 |

Each XOR takes the counter bit on its A input (pins 1, 4, 9, 12) and a
common rail on its B input (pins 2, 5, 10, 13). That rail is FLIP, buffered
through an inverter at 7J, and FLIP itself enters at the top left of the
sheet from CN1. The `E` suffix in the CENTER PCB signal names (H1E, V1E,
H4E, V16E, H64E) marks these XORed outputs, not a drawing convention.

This answers the one question the flip implementation could not settle from
MAME: **flip is applied to the counters, and scroll is added afterwards.**
The CENTER PCB - which holds the VRAM, the scroll adders and the tilemap
address generation - only ever sees already-inverted counters, so there is
no path by which scroll could be applied first. The core mirrors each
layer's coordinate and then adds scroll, which matches.

It also explains why so little else needs flip-specific logic on the real
board: sprite position comparison, tile fetch, panel addressing and video
blanking are all downstream of the XORs and invert for free.

**The panel's horizontal window is a magnitude comparator.** CENTER PCB
sheet 4 of 4 (page 35) has a 74LS85 at 2B comparing H counter bits on its B
inputs (pins 9, 11, 14, 1, fed from H64E among others) against a constant on
its A inputs (pins 10, 12, 13, 15), where A0 is driven by FLIP itself. Its
A<B output (pin 7) leaves as PSOUT on CN1 28A. So the panel strip is
positioned by a comparison whose threshold FLIP adjusts, on top of the
already-inverted counters - consistent with the panel moving from the right
edge to the left edge when flipped.

The same sheet shows the panel RAM address multiplexers: three 74LS157 at
6F, 6H and 6J selecting between the CPU address (A0B..A10) and the video
address, which is H4E, H8, H16, H32 on RAMA0..3 and V1E, V2, V4, V8, V16E,
V32, V64 on RAMA4..10. Four pixels per byte and sixteen bytes per row, which
is the layout the core and MAME both use.

The score panel is addressed straight from the counter
------------------------------------------------------

**CENTER PCB sheet 4 of 4 (page 35).** The 74LS157 at 6F takes H4E, H8,
H16 and H32 on pins 5, 2, 11 and 14 and drives RAMA0..3, so the panel RAM
column is `h_eff(5 downto 2)` and the pixel within the byte is
`h_eff(1 downto 0)`, where `h_eff` is the horizontal counter after the
flip XORs on BOTTOM sheet 1. The CPU port of the same mux takes A0..A3
straight from the write address, so neither side carries an offset. There
is no adder and no prefetch anywhere in the path.

That leaves one free parameter: the lag between the counter value that
addresses the RAM and the pixel reaching the screen. Solving the board's
column against MAME's model - which writes source `4*(sx-1)+i` to column
`sx`, and shows source `p-200` at screen `p` - gives **LAG = 4** uniquely
across the whole window. Independent check: the core's hardware-verified
unflipped offset is -455, and -451 - LAG is -455.

**Consequence for flip.** Unflipped the lag is invisible; it only selects
which column is fetched. Flipped it is not, because the counter mirrors
and the lag does not. But the flipped window is not a mirror either - see
the comparator below - and an earlier conclusion here ("hardware says LAG =
0, the flipped panel is the plain mirror") was wrong: it came from testing
against MAME's flush-left layout as the target, which the board does not
produce.

**The panel window is PSOUT from the 74LS85 at 2B**, and the comparator is
fully readable (CENTER sheet 4, page 35; the jumper straps were confirmed by
the user reading `schematic_1a` at high zoom):

- B inputs: H8, H16, H32 tapped off the 6F mux input lines, plus H64E -
  so B = `h_eff(6 downto 3)`, 8-pixel steps.
- A inputs: A3 (pin 15) strapped to +5V, A2 and A1 (pins 13, 12; the
  second "2" on the left of the chip is a drafting slip for 12) strapped to
  ground, A0 (pin 10) on the FLIP net.
- Cascade: A<B-in (pin 2) on +5V; A=B-in and A>B-in (pins 3, 4) on FLIP.
- Output: A<B-out (pin 7) is PSOUT.

The FLIP net is high when the screen is *not* flipped. That is the only
reading that yields the known 48-pixel unflipped window (h_eff 208..255),
and it agrees with the inverter at 7J feeding the counter XORs. Flipped,
A drops to 8 and equality now counts, so the window opens to h_eff
192..255: **64 pixels wide, screen x 0..63**. With the 4-pixel data lag:

| screen x (flipped) | shows |
|---|---|
| 0..7 | RAM columns 0 and 15 - inside the window, never drawn by MAME |
| 8..63 | panel source 55 down to 0 (source 0..7 are never visible unflipped) |

So on a real cocktail cabinet the flipped panel is 64 pixels wide and its
content starts 8 pixels in from the left edge. MAME's `clippanelflip`
0..47 is not what the board does; together with the out-of-range 0x2c8
write, MAME's flipped panel should be regarded as a guess.

One measured correction remains in the core, `M58_PANEL_WIN_ADJ = -6`: our
own flipped path sat six pixels right of this model on hardware (a photo
with both blanking edges visible). That is a property of the core's
pipeline, not of the board, and it is unexplained.

Open questions the schematics could still answer
------------------------------------------------
- **Sprite-per-line limits.** Real hardware drops or flickers sprites past a
  threshold; the core does not reproduce this.
- **Sound board mixing ratio.** The ADPCM low-pass is now modelled (see the
  sound section); the AY-to-ADPCM level set by R15 and R25 is not. R15
  reads 2.2K from a photo; turning that into a core gain needs the source
  levels too, or a recording from a board.
- **Why the core's flipped panel path sits six pixels right of the board
  model.** Measured and corrected (`M58_PANEL_WIN_ADJ`), not explained.
- **What the game leaves in panel RAM columns 0 and 15.** They show in the
  flipped window on the board; MAME discards writes to them.

Accuracy tiering
----------------

This core is a behavioural model built from MAME's driver, layered on the
MiSTer M62 core (itself derived from the PACE framework). It is not a
schematic-level recreation. The palette is now the one subsystem verified
against both MAME's model and Irem's schematics; everything else rests on
MAME's interpretation of the hardware. The flip path is the second
subsystem whose structure - counters inverted ahead of everything else - is
taken from the schematics rather than inferred.
