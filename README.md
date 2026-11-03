# IRON VEIL

Native Meta Quest tactical PvE prototype built with Godot 4 and OpenXR.

## Current prototype features
- OpenXR head and controller tracking
- Smooth thumbstick locomotion and turning
- Grip-button rifle pickup/drop and trigger firing
- Low-poly carbine, controller gloves, and CQB silhouette targets
- Procedural suburban street block with house shells and vehicle props
- Procedural sky, ambient lighting, fog, and subtle surface variation
- Transparent muzzle-flash PNG generated and cached at runtime
- CC0 rifle-shot and concrete-footstep MP3 effects downloaded and cached on first launch

## Free asset sources
- Kenney City Kit (Suburban), CC0: https://kenney.nl/assets/city-kit-suburban
- OpenGameArt muzzle-flash PNG pack, CC0: https://opengameart.org/node/179598
- SFXMint rifle shot and concrete footsteps, CC0: https://sfxmint.com/sounds/impact-gunshot-08 and https://sfxmint.com/sounds/footsteps-concrete-75

The current prototype generates its muzzle-flash sprite locally and downloads the two CC0 audio effects on first launch. The Kenney and OpenGameArt packs are listed as future art-source options; their model/sprite files are not yet bundled in this repository.

## Open the project on Quest 3
1. Download this repository as a ZIP from GitHub and extract it with a Quest file manager.
2. Import the extracted folder into Godot on Quest.
3. Confirm OpenXR is enabled and run the project.
4. Allow the app to access the internet on first launch so it can fetch the CC0 sound effects. The audio files are cached locally after a successful download.

The first goal is to verify the scene launches correctly in the headset. APK export and the required Android build environment are a separate step.

## Important testing note
This is an early prototype. The latest visual and audio changes have not been tested on a physical Quest headset by the developer. Internet access is required for the first audio download. If the downloads fail, the project will log a warning and the corresponding sound will be silent until the download succeeds.

