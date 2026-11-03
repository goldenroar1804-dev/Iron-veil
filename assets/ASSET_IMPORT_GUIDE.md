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

## Environment and hands (implemented visual-only overrides)

Optional files are loaded automatically when present:

- `assets/models/environment/suburban_house.glb` — used for each of the eight house visuals.
- `assets/models/environment/sedan.glb` — used for each parked-car visual.
- `assets/models/hands/left_hand.glb` — left tracked-hand visual.
- `assets/models/hands/right_hand.glb` — right tracked-hand visual.

House and vehicle replacements hide only the matching procedural `MeshInstance3D` visuals. The original `StaticBody3D` and `CollisionShape3D` nodes are deliberately retained, so door openings, wall blocking, vehicle blocking, and player collision do not depend on imported model meshes. If a file is absent or fails to load, the procedural visual remains visible. Imported hands are attached beneath their existing tracked controller; a procedural hand is used if the relevant file is absent.

### Suggested authoring dimensions

- House: approximately 7.7 m wide × 3.6 m high × 6.2 m deep, front entrance facing local −Z.
- Sedan: approximately 1.8 m wide × 1.5 m high × 4.2 m long, front facing local −Z.
- Hands: palm centered near the origin, wrist toward local +Z, fingers toward local −Y; author at real-world scale (roughly 0.18–0.22 m from wrist to fingertips).
- Apply transforms before exporting. Keep meshes low-poly and textures at 1K or smaller for Quest.

## Free asset sources to review

- Kenney — City Kit Suburban: https://kenney.nl/assets/city-kit-suburban
- Quaternius — game-ready 3D asset packs: https://quaternius.com/ (check the current per-pack and site license before committing or redistributing files; terms can change).
- Poly Haven — CC0 PBR textures and HDRIs: https://polyhaven.com/
- Freesound — audio library; check each individual file's license before use: https://freesound.org/

Do not assume every asset on an aggregator has the same license. Record the exact asset page, creator, license, and any attribution requirement in a small text file next to each imported pack. Only commit files whose license permits redistribution in this public repository.

## Quest performance and safety checks

1. Prefer GLB files with baked/packed materials and modest texture sizes (typically 1K or smaller for environment props).
2. Keep the rifle mesh reasonably light and avoid high-poly subdivision at runtime.
3. Test model scale and grip alignment in headset before removing procedural fallbacks.
4. Do not remove or replace existing static collision bodies as part of a visual-only asset import.
5. Test the build on the target Quest headset; desktop editor success is not a substitute for headset testing.


## Import checklist

1. Put each GLB at the exact path above; filenames and case must match.
2. Open the project in Godot and allow the GLB importer to finish before running.
3. Confirm each model's scale, front direction, materials, and controller alignment in the editor.
4. Run the project and inspect every house doorway and vehicle clearance. The existing colliders remain active, but a badly scaled visual can still look misaligned with them.
5. Keep the source asset URL and its exact license in `CREDITS.md` before distributing the project. Kenney states its game assets are CC0; verify the license included with the specific download. Quaternius terms should be checked on the current license page and individual pack page.
