# Santa Claus in Trouble — iOS Engine

An iOS port of the classic 2002 PC game **"Santa Claus in Trouble"** using **Metal** and **C++**.

## Status
- ✅ XPK archive parsing (177 assets)
- ✅ MSZIP decompression (DirectX .x files)
- ✅ 3D skinned mesh rendering via Metal
- ✅ DDS texture decoding (RGB565, RGB888, RGBA8888)
- ✅ Bone/skinning support
- 🔄 Texture mapping (in progress)
- ⏳ Animation, physics, game logic

## Architecture

| Folder | Contents |
|--------|----------|
| `src/` | C++ engine (XPK parser, X-File parser, DDS decoder) |
| `ios/` | iOS wrapper (AppDelegate, MetalView, GameEngine, Shaders) |
| `assets/` | Game data (`xmas.xpk` — 15.5 MB, 177 files inside) |
| `.github/workflows/` | CI/CD pipeline (auto-builds unsigned IPA) |

## Building

Push to `main` — GitHub Actions automatically:
1. Compiles the C++ test binary
2. Generates the Xcode project with XcodeGen
3. Builds the iOS app
4. Packages the unsigned `SantaEngine.ipa`
5. Uploads the IPA as a build artifact

No Mac required — everything runs on GitHub's macOS runners.

## Credits

Original game © 2002 **CDV Software Entertainment AG** / **Joymania Development**.
This is a fan-made reverse-engineering project for educational purposes.
