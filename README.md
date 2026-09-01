# godot-apk

A minimal Godot 4 "Hello World" project, set up to be exported to an Android
debug APK from the command line and built automatically by GitHub Actions.

## Project contents

- `project.godot` – Godot 4.3 project configuration.
- `main.tscn` – the main scene, a single `Label` node that displays
  `Hello World`.
- `icon.svg` – the project icon.
- `export_presets.cfg` – the Android export preset used to build the APK
  (application id `com.example.helloworld`, output path
  `build/android/hello-world.apk`).
- `.github/workflows/android-apk.yml` – CI workflow that builds the Android
  APK on every push, pull request, and manual trigger.

## Running the project locally

1. Install [Godot 4.3](https://godotengine.org/download) (stable).
2. Open the Godot editor and choose "Import", then select the
   `project.godot` file in this repository.
3. Press `F5` (or the "Run" button) to run the project. The main scene
   will display the text `Hello World`.

You can also run the project headlessly from the command line, without
opening the editor UI:

```sh
godot --headless --path . main.tscn
```

## Building the Android APK locally

To export the debug APK from the command line you need:

- The Godot 4.3 editor binary (`godot`).
- The matching [export templates](https://godotengine.org/download) for
  4.3, installed via the editor's "Manage Export Templates" dialog (or
  extracted manually into
  `~/.local/share/godot/export_templates/4.3.stable/`).
- A configured Android SDK (platform-tools and build-tools) and a JDK, with
  the SDK path and a debug keystore set in the editor's Editor Settings
  (`Export > Android`), or in `export_presets.cfg`.

Once everything is configured, build the APK with:

```sh
mkdir -p build/android
godot --headless --export-debug "Android" build/android/hello-world.apk --path .
```

The resulting APK is written to `build/android/hello-world.apk`.

## Continuous Integration

The [`android-apk.yml`](.github/workflows/android-apk.yml) workflow:

- Triggers on `push`, `pull_request`, and `workflow_dispatch`.
- Runs on `ubuntu-latest`.
- Installs a JDK, the Android SDK command line tools/platform/build-tools,
  the Godot 4.3 editor, and the matching export templates.
- Generates a debug keystore and configures the editor settings needed for
  Android export.
- Runs `godot --headless --export-debug "Android" build/android/hello-world.apk`
  to build the APK.
- Uploads the resulting APK as a workflow artifact named
  `hello-world-apk` using `actions/upload-artifact`.

**Note:** the workflow intentionally does **not** use `actions/cache` or any
other caching mechanism (no cache options on setup actions, no manual
restore/save steps). Every run performs a clean build from scratch.
