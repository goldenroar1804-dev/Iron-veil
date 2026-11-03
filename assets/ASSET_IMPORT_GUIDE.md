# Optional imported assets for IRON VEIL

This repository stays runnable without third-party downloads. The procedural rifle and existing environment remain the fallback. Imported files are optional overrides and must be copied into the paths below.

## Weapon model (implemented)

- Path: `assets/models/weapons/m4_carbine.glb`
- Format: Godot-importable GLB/glTF 2.0.
- Authoring scale: approximately 1.0 Godot unit = 1 metre; total rifle length about 0.8–1.0 m.
- Orientation: stock toward local +Z, muzzle toward local -Z, top of weapon toward +Y.
- Keep the origin near the receiver / weapon grip so the existing controller attachment remains sensible.
- Use a low-poly / mobile material setup; avoid 4K textures, expensive transparency, and excessive material slots.
- The game automatically loads this file when present. Otherwise it builds the existing procedural M4-style fallback.

## Audio (implemented)

Bundled audio is preferred over network downloads when present:

- `assets/audio/rifle_shot.ogg` (also accepts WAV or MP3)
- `assets/audio/footsteps_concrete.ogg` (also accepts WAV or MP3)

Use short, mono or stereo effects suitable for spatial playback. Keep source and license information alongside any imported file. If no local file exists, the prototype retains its existing CC0 SFXMint download-and-cache fallback.

## Environment and hands (planned slots; not yet wired)

Suggested future locations:

- `assets/models/environment/suburban_house.glb`
- `assets/models/environment/sedan.glb`
- `assets/models/hands/left_hand.glb`
- `assets/models/hands/right_hand.glb`

These are not active overrides yet. The current house, car, and hand geometry remains procedural so existing collision shapes, door clearances, and controller tracking are not accidentally changed by an unverified model.

## Free asset sources to review

- Kenney — City Kit Suburban: https://kenney.nl/assets/city-kit-suburban
- Quaternius — free game-ready 3D asset packs: https://quaternius.com/
- Poly Haven — CC0 PBR textures and HDRIs: https://polyhaven.com/
- Freesound — audio library; check each individual file's license before use: https://freesound.org/

Do not assume every asset on an aggregator has the same license. Record the exact asset page, creator, license, and any attribution requirement in a small text file next to each imported pack. Only commit files whose license permits redistribution in this public repository.

## Quest performance and safety checks

1. Prefer GLB files with baked/packed materials and modest texture sizes (typically 1K or smaller for environment props).
2. Keep the rifle mesh reasonably light and avoid high-poly subdivision at runtime.
3. Test model scale and grip alignment in headset before removing procedural fallbacks.
4. Do not remove or replace existing static collision bodies as part of a visual-only asset import.
5. Test the build on the target Quest headset; desktop editor success is not a substitute for headset testing.
