# Spine Image Replacer

A native macOS companion for Spine 4.2. It visually attaches a **Replace Images** button to the active Spine window without modifying or injecting code into `Spine.app`.

## Animator workflow

1. Open Spine 4.2 and launch **Spine Image Replacer**.
2. Click the attached **Replace Images** button in the top-right of the Spine window.
3. The open `.spine` project is selected automatically when macOS can identify it. Click **Detect** to retry, use **Choose…**, or drag the `.spine` file from Finder onto the project row. Drag the current loose PNG folder and new-images folder onto their rows, or choose them normally.
4. Click **Scan Images** and review every result and preview.
5. Click **Apply with Backup**. The live PNG folder is updated atomically, so Spine reloads it.
6. Use **Undo Last Replacement** if the artwork needs to be restored.

Replacement PNGs are matched by exact relative path. The tool preserves the original canvas and automatically moves replacement artwork back to the original non-transparent bounds. It never scales changed artwork silently; different visible dimensions are blocked.

Before applying, the complete current-images folder is copied beside itself using an `_old` suffix. For example, `images` becomes `images_old`. Existing snapshots are preserved as `images_old_2`, `images_old_3`, and so on. Transactional backups used by **Undo** are also stored beside the `.spine` project under `.spine-image-replacer-backups/`.

The companion remembers the current-images folder for each project. Project detection uses the active Spine process, its open files, and its window title. When detection is unavailable or ambiguous, the project picker remains available and nothing is guessed.

Drag-and-drop accepts exactly one item at a time. Project rows accept only `.spine` files; image rows accept only folders. A drop only fills the field and never starts scanning or replacement automatically.

## Build

Requirements: macOS 13 or later and Xcode with the Swift toolchain.

```bash
./scripts/build_app.sh
```

The script creates:

- `dist/Spine Image Replacer.app`
- `dist/Spine Image Replacer.zip`

The local build is ad-hoc signed. For frictionless studio distribution, sign and notarize it with the studio's Apple Developer ID. Otherwise, animators can right-click the app and choose **Open** the first time macOS asks for confirmation.

## Boundary

The attached control is a window overlay owned by the companion app. Spine 4.2 has no editor plugin API, so the tool does not patch the Spine binary or add an actual internal menu command. The overlay appears only while Spine is the active application and follows its window.
