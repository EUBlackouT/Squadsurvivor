# How to Share Squad Protocol with Your Friend

## Option 1: Export from Godot Editor (Easiest)

1. **Open the project in Godot 4.4**
   - Double-click `godot/project.godot`

2. **Install Export Templates** (first time only)
   - Go to `Editor` → `Manage Export Templates`
   - Click `Download and Install`
   - Wait for download to complete

3. **Export the game**
   - Go to `Project` → `Export...`
   - Select `Windows Desktop` preset (already configured)
   - Click `Export Project`
   - Choose where to save (e.g., `builds/SquadProtocol.exe`)
   - Uncheck "Export With Debug" for smaller file

4. **Share with friend**
   - Zip the exported `.exe` file
   - Send via Discord, Google Drive, etc.
   - Friend just downloads, extracts, and runs!

---

## Option 2: Use Build Script

Run from PowerShell:
```powershell
cd E:\SplitCode
.\scripts\build_game.ps1
```

If Godot isn't found automatically:
```powershell
.\scripts\build_game.ps1 -GodotPath "C:\path\to\Godot.exe"
```

---

## Option 3: Let Friend Run from Source

If your friend has Godot 4.4 installed:

1. Zip the entire `godot/` folder
2. Send the zip
3. They extract and open `project.godot` in Godot
4. Press F5 to play

---

## Quick Sharing Checklist

- [ ] Export templates installed in Godot
- [ ] Game exported to .exe
- [ ] Zipped the build folder
- [ ] Sent to friend
- [ ] Friend extracted and ran SquadProtocol.exe

## Controls (remind your friend!)

- **WASD** - Move
- **Shift** - Dash
- **Q** - Overclock (power boost)
- **F** - Class Callout (special ability)
- **1-4** - Formation modes
- **T** - Target mode cycle
- **LMB** - Focus fire
- **RMB** - Rally point


