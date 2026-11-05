# Mikrozz

**Mikrozz** is a portrait-mode pastel physics maze game for Android, built with Godot 4.4.1 and GDScript.

## Play
- Tilt the phone to roll the ball; desktop testing uses arrow keys / WASD through Godot's built-in UI actions.
- Hold the on-screen pastel buttons to open matching gates.
- Coins are rigid-body objects and respond to the same tilt force as the ball.
- Avoid spike and pit hazards, reach the exit, and keep your three lives.
- Each new level increases maze density, gate count, hazards, and moving traps.

## Build
See BUILDING.md. GitHub Actions builds a signed debug APK on every push to main, every v* tag, or manual workflow dispatch. Download PastelMaze.apk from the PastelMaze-Android artifact on the Actions run.

## Project
- project.godot — Godot project settings
- export_presets.cfg — Android export preset
- scripts/ — game logic, physics, procedural maze, tilt and UI
- scenes/ — reusable scene resources
- .github/workflows/android_build.yml — CI build pipeline

The CI debug key is temporary and intended for testing only.
