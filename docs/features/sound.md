# Sound

A calm, living soundscape that follows what the camera sees. Every sound is made from nothing at
boot (noise, sines, a few filters); there are no sample files and no third-party audio. Sound
only reads the world, and draws its dice from its own `RandomNumberGenerator`.

Code: `scripts/audio/` (`SoundSynth` recipes, `SoundBank` render and cache, `SoundMixer` the
rules, `Soundscape` the live node, `SoundSettings` buses and volumes), `scripts/systems/AudioSystem.gd`
(Main's handle, keeps the old `play_*` calls), `default_bus_layout.tres`. Tests:
`tests/suites/74_sound.gd`.

## What you hear

| Layer | Kind | Chosen by |
|---|---|---|
| Surf | bed | how much of the ground round the ear is sea (rings of tile samples, off-map counts as sea); heavier in a storm |
| Wind | bed | a breath on the ground, more the higher the camera, a lot in a storm, a little more in winter and by the sea |
| Rain on leaves / in the open | beds | rain where you're looking (`WeatherSystem.overcast_at` at the focus), split by how wooded it is round you |
| Crickets | bed | warm nights over land (summer most, none in winter); rain hushes them |
| Bird chorus | bed | dawn (04:30-09:00) in spring above all; a thin bed by day; over land, woods most; rain hushes it |
| Birdsong, doves, gulls, owls | calls | rates from the same rules (gulls by day toward the sea, owls at night in woods) |
| Frogs | calls | the ambient frogs' own croaks (`AmbientLife.frogs`) within earshot, and more by rivers at night |
| Sheep, cows | calls | herds within earshot, now and then (quieter at night) |
| Wolves | calls | at night, heard from three times as far, never loud ("far off") |
| Thunder | call | every bolt `WeatherView` draws: arrives `d / 343 × 3` s late (the island is small; the wait is the pleasure), near ones crack, far ones only roll |
| Fire | spot | the two loudest fires (`World.natural_fires`, grouped by 4-tile cells so a burning wood roars as one) |
| Voices | spot | the two liveliest groups of awake people (6-tile cells, two or more); syllables, phrases and laughs with no words, muffled |
| Festival band | spot | while a festival runs (see the hook below): a pipe and frame drum |
| Stingers | UI | album moment (three glass notes, the gentle chime), discovery (two kalimba notes), birth (a music box), death (one low bell), achievement, disaster |

**The two ears.** The wisp's ear is at its head (point sources at half level at 9 m, gone by
60 m). The sky's ear hangs over the focus at 0.35 of the camera distance, with a wider reach
(`10 + 0.28 × distance` m to half level) but less of the small close detail as you rise, so a
single hearth fades as you climb while the beds (surf all round, wind) carry the island as a
whole. All of it is `SoundMixer.hearing()` and `falloff()`.

## Mixing

Buses: Master (hard limiter at -0.5 dB) ← Ambience (beds, spots), Effects (calls; a touch of
reverb), UI (stingers). Volumes for each, and Hush, are on the Look screen (`SoundSettings.panel()`),
kept in `user://sound_settings.json`. **N** hushes everything and says so.

Stingers repeat at most every few seconds per kind (births 6 s, deaths 8 s), so a busy day at 20×
stays calm.

## Cost

- **Render once, off the main thread.** About 158 s of mono 22 kHz audio, 1-2 s of CPU (5-11 s
  wall on a loaded 4-core box) on a low-priority thread started by the first `Soundscape`; loops
  are wired in as soon as it finishes. Boot doesn't wait for it. The bank is static, so a new island
  or a second Main reuses it.
- **Per frame**: easing about a dozen volumes, rolling call chances, the thunder queue: about
  0.2 ms. **Five times a second** a survey (about 40 tile reads, the fires, the living, the frogs):
  about 0.8 ms on a loaded machine.
- `tools/profile.gd` drives `Main._process` by hand, so the soundscape's own `_process` isn't in
  its numbers; it doesn't touch the simulation's frame either.

## Seamless loops

Noise beds are rendered 0.75 s long and the tail crossfaded (equal power) into the head; beds of
events (drops, chirps, crackles, notes) add each event modulo the loop length, so what rings past
the end comes back at the start. The test checks every loop's seam is below a click, no buffer
clips, and the album chime peaks at 0.6 or less.

## Hooks

- `AudioSystem.on_festival_started(kind, pos)` / `on_festival_ended(kind, pos)`: `pos` a tile
  `Vector2` or metres `Vector3`; extra arguments are ignored, so a festival signal can connect
  straight to them. A flourish plays (louder if you're near), then the band, at 2.5× the usual
  reach, until it ends or 60 game-seconds pass.
- `AudioSystem.play_moment()` (Main's `_on_moment` calls it) or `on_moment(id, title)`.
- `WeatherView.struck(ground)`: emitted by every bolt; the soundscape connects itself.

## Open

- Surf is not directional (one stereo bed); gulls are placed toward the sea.
- Footsteps for the wisp, and rain on roofs in towns, are not there.
- `play_weather_change()` has a sound but nothing calls it.
- The festival band is one tune; kinds of festival could pick their own.

## Lessons

- **GDScript DSP is cheaper than feared, but not free.** A noise sample through a one-pole filter
  costs about 0.2 µs, a `sin` about 0.1 µs. Envelopes, formants and filter coefficients worked
  out per sample (an `exp` or `pow` each) made thunder, animals and surf 3-4× slower than
  needed; computing them every 32-64 samples ("control rate") gave the same sound. Rule: per
  sample only what must move per sample.
- **A tool that drives `_process` by hand can't see other nodes.** `tools/profile.gd` calls
  `Main._process` in a loop, so anything ticking in its own node is invisible to it. Measure
  such nodes separately (the bench in this note's numbers called `Soundscape.tick` directly).
