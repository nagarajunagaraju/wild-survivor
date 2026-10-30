# Wild Survivor

**Run. React. Decide. Survive.**
A 3D forest survival runner for Android. A tiger is hunting you; dodge obstacles, keep your energy and water up, and read the clues at every fork to pick the safe path.

## Download (phone)
Open **Releases** on this repo from your phone: `https://github.com/nagarajunagaraju/wild-survivor/releases/latest`
Tap the `.apk` file, then allow installs from your browser when Android asks.

Every push to `main` builds a fresh APK automatically (Actions tab).

## What's in the game
- Remy: realistic rigged character with Mixamo motion-capture idle, run, jump, hit and death animations
- Ranger and Shadow (unlocks for 300 coins) as extra runners
- Swipe controls: left/right lanes, up jump, down slide (arrow keys on desktop)
- Tiger chase: a striped, galloping tiger with snapping jaws closes in when you get hit; the camera rises so you see it behind you
- Crocodile that lunges and snaps when you pick its lane; bear that rears up out of the den roaring
- Obstacles: boulders, stumps, logs, snakes, low branches, charging boars, falling trees
- Fork decisions read from clues: river (crocodile / slippery rocks / logs), gorge (bridges), rock wall (bear den / thorns / daylight), rockslide (shadows), forest fire (flames / embers / stream)
- Survival: health, energy (fruit), water (bottles), first-aid kits
- Power-ups: Shield, Magnet, Slow-mo, Double jump, each with an on-screen timer
- Modes: Endless, Daily (same seeded course for everyone each day, best saved), Hardcore (1.6x damage, one wrong fork ends the run, double coins)
- 19 missions (+50 coins each), coin wallet, character unlock, saved progress
- Textured dirt road, wind-swept grass, sky with sun, drifting clouds and stars, rippling river water
- Footstep dust, landing dust, water splashes, rain splashes, fire sparks, coin sparkles
- Recorded sound: forest ambience, rain, thunder, river, fire, running footsteps synced to speed, breathing that gets heavier as energy drops, heartbeat as the tiger closes in, tiger roar, falling trees, splashes (credits in `www/sounds/CREDITS.txt`)
- Day/night cycle, rain and thunderstorms, fireflies
- Graphics High/Low setting for slower phones

## Project layout
- `www/` – the game (three.js r128, offline; models in `www/models/`)
- `android/` – Capacitor 7 Android wrapper (portrait, full-screen, keeps screen on)
- `.github/workflows/android.yml` – builds the APK (and the Play Store AAB once signing is set up)

## Play Store build (when you're ready)
Google Play needs a signed `.aab`. Create an upload key once on your PC (keep it safe; losing it blocks updates):
```
keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```
Then in GitHub: **Settings → Secrets and variables → Actions → New repository secret**, add:
- `ANDROID_KEYSTORE_BASE64` – output of `base64 -w0 upload.jks` (on Windows: `certutil -encode upload.jks out.txt`, paste the middle lines)
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS` – `upload`
- `ANDROID_KEY_PASSWORD`

The next build will attach `WildSurvivor-1.0.N.aab` to the release. Upload that in Play Console.

## Before a public release
- Remy and his animations were exported from your Mixamo account. Ranger and Shadow come from the three.js example set (Mixamo-sourced); replace them with your own Mixamo exports before publishing.
- Add a privacy policy page and store screenshots.
- New personal Play Console accounts must run a closed test with 12 testers for 14 days before production.

## Run locally
Serve `www/` with any static server, e.g. `npx serve www`, and open it in a browser.
