// fold — fat color bands torn and refolded by a pixelated noise field; datamoshed sunset.
// Arc: bands start lightly torn, the tear and its block size grow to a peak, ease back,
// then the piece snaps to clean (untorn) posterized bands for the ending.
const h = rand()
const pick = (xs) => xs[Math.floor(rand() * xs.length)]

// Seeded structure: band count/orientation, tear axis, tear-block layout, snap timing.
const bandFreq = 3.5 + rand() * 3.5 // fat bands across the frame
const bins = pick([4, 5, 6]) // posterize levels
const tearOnX = rand() < 0.5 // which axis the pixelated noise rips along
// Bands run across the tear so the rips read; seeded tilt off that axis.
const bandAngle = (tearOnX ? 0 : Math.PI / 2) + (rand() - 0.5)
const cellsX = 6 + Math.floor(rand() * 16) // tear-block grid at peak
const cellsY = 6 + Math.floor(rand() * 16)
const snapT = dur * (0.86 + rand() * 0.05)

const peakIn = dur * 0.6
const peakOut = dur * 0.8

// Tear amount: light opening, builds to above the draft's 0.4, flutters at the peak, eases back.
const tear = () =>
  (ramp(0, peakIn, 0.1, 0.6) + ramp(peakOut, snapT, 0, -0.45)) *
  (1 + 0.2 * lfo(9) * ramp(dur * 0.4, peakIn, 0, 1) * ramp(peakOut, snapT, 1, 0))
const fold = () => ramp(0, peakIn, 0.5, 0.9) + ramp(peakOut, snapT, 0, -0.3)
// Tear-block grid coarsens (fewer, bigger blocks) toward the peak; integer steps only.
const coarse = () => ramp(0, peakIn, 2.2, 1) + ramp(peakOut, snapT, 0, 0.8)
const blockX = () => Math.round(cellsX * coarse())
const blockY = () => Math.round(cellsY * coarse())
// Datamosh pixelation: fine at the opening, chunky at the peak, partly recovering in cooldown.
const pixOffset = () => Math.round(ramp(0, peakIn, 220, 30) + ramp(peakOut, snapT, 0, 110))
const pixMultiple = () => Math.round(ramp(0, peakIn, 120, 320) + ramp(peakOut, snapT, 0, -120))

const bands = () => osc(bandFreq, 0.04, 2.2).rotate(bandAngle).posterize(bins, 0.8)
const tearField = () => noise(3, 0.12).pixelate(blockX, blockY)

const torn = bands().modulateScrollY(osc(2.5, 0.03).rotate(0.4), fold)
const ripped = tearOnX
  ? torn.modulateScrollX(tearField(), tear).modulateScrollY(tearField(), () => tear() * 0.25)
  : torn.modulateScrollY(tearField(), tear).modulateScrollX(tearField(), () => tear() * 0.25)
ripped
  .modulatePixelate(noise(2, 0.05), pixMultiple, pixOffset)
  .hue(h)
  .saturate(1.4)
  .contrast(1.2)
  .out(o0)

// Snap clean: the same bands, untorn, settling into a slow fold for the ending.
at(snapT, () => {
  bands()
    .modulateScrollY(osc(2.5, 0.03).rotate(0.4), () => ramp(snapT, dur, 0.6, 0.25))
    .hue(h)
    .saturate(1.4)
    .contrast(1.2)
    .out(o0)
})
