# Building Mikrozz for Android

## Requirements
- Godot 4.4.1 standard build and matching export templates
- JDK 17 and Android SDK platform/build-tools 35
- Android device with an accelerometer

## Local build
1. Install Godot 4.4.1 and its export templates.
2. Install Android SDK platform 35 and build-tools 35.0.0.
3. Create a debug key in the project root:

```bash
keytool -genkeypair -v -keystore debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
```

4. Open the project in Godot once, then run:

```bash
godot --headless --editor --path . --quit
godot --headless --path . --export-debug Android build/PastelMaze.apk
```

The APK is written to `build/PastelMaze.apk`.

## GitHub Actions
Pushes to `main`, version tags (`v*`), and manual dispatch trigger the Android build. The workflow pre-imports the project before export to warm the Godot resource cache. The APK is uploaded as a 14-day artifact named `PastelMaze-Android`.

CI generates a temporary debug keystore. This is suitable for testing, not Play Store distribution. Use a private release keystore and protected GitHub secrets for production.

## Controls
- Tilt the phone to roll the ball.
- Hold the pastel gate buttons to open gates.
- Collect moving coins, avoid spikes and holes, and reach the exit.
- A run has three lives; losing one rebuilds the room and restores coins.
