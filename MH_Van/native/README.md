# MH Van Native Extension

This folder contains the optional C extension for MH_Van.

The extension is intentionally small in v1:

- Ruby still reads and writes the live SketchUp model.
- Ruby still performs hide/show/select/isolate through the SketchUp Ruby API.
- Native C groups prepared board scan items into rows.
- Native C also provides the shared AABB distance-clustering matcher used by
  `MH::Geo::Cluster` (and therefore Fast Rename) for sets up to 2,000 boxes.
- If the native extension cannot be loaded, MH_Van falls back to the Ruby grouping path.

Expected compiled extension name:

```text
MH_Van/native/mh_van_native.so
```

or:

```text
MH_Van/native/build/mh_van_native.so
```

Build from a Ruby environment compatible with the SketchUp Ruby version.
SketchUp 2025 on this machine has `Tools/gems/3.2.0`, so use a 64-bit Ruby
3.2.x toolchain unless SketchUp's Ruby Console says otherwise.

```powershell
cd MH_Van/native
.\build.ps1
```

Before building, verify the Ruby that will compile the extension:

```powershell
ruby -rrbconfig -e "puts RUBY_VERSION; puts RbConfig::CONFIG['arch']; puts RbConfig::CONFIG['MAKE']"
```

The Ruby version, CPU architecture and compiler family must match the Ruby ABI
embedded by SketchUp. Do not mix a 32-bit Ruby with 64-bit SketchUp, or a Ruby
3.3/3.4 build with SketchUp's Ruby 3.2 ABI.

Recommended Windows setup:

1. Install **RubyInstaller 3.2.x x64 with DevKit**, then run `ridk install`.
2. Open a fresh PowerShell where `ruby` is in `PATH`.
3. Run `.\build.ps1` from this folder.

If using a Visual Studio Ruby build instead, open a Visual Studio Developer
PowerShell so Ruby's configured make tool and compiler are available.
