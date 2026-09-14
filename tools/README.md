# Updating this repository after a change in Studio

Scripts do not need exporting. Studio cannot write files, but it can make HTTP
requests, so the sync runs the other way: a small local server listens and
Studio pushes every script to it.

## Scripts — automatic

1. Save the place in Studio (**Ctrl+S**).
2. Start the receiver:

   ```powershell
   python tools/studio_sync_server.py
   ```

3. In Studio, **Edit mode**, paste `tools/capture.lua` into the command bar and
   run it. It walks ReplicatedStorage, ServerScriptService, ServerStorage,
   StarterPlayer, StarterGui, StarterPack and Workspace, and posts the source of
   every script to the server, which writes them into `src/`.
4. Stop the server with Ctrl-C, then:

   ```powershell
   .\tools\push-update.ps1 "what changed"
   ```

   It shows the diff and asks before pushing.

`capture.lua` only reads. It enables `HttpService.HttpEnabled` for the duration
and restores the previous value afterwards.

## Geometry — manual, and usually unnecessary

`export/Export.gltf` is the only part that needs a manual step, because mesh
export is a menu action with no Luau equivalent:

**File → Export Selection…**, choose `.gltf`, save over `export/Export.gltf`.

You rarely need to. The world is generated, so `generator/SeedLabGenerator.lua`
is the real source of the geometry; the glTF is a convenience for viewing it
outside Roblox. Note also that GitHub rejects any file over 100 MB, so the OBJ
export (194 MB) cannot go in the repository — `.gitignore` excludes `*.obj` and
`*.mtl` for that reason.

## Documentation

If you changed the LaTeX under `docs/`:

```sh
cd docs && ./compile.sh
```

Delete `*.aux`, `*.out` and `*.toc` first if you added or removed a chapter —
stale bookmark entries cause `! File ended while scanning use of \BKM@entry`.
Close the PDF in any viewer before rebuilding, or the write fails with
`I can't write on file`.
