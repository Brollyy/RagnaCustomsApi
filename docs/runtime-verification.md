# Runtime Verification

Build and verify the RagnaModManager package:

```bash
python3 scripts/package.py --output dist/RagnaCustomsApi.rmod
python3 scripts/verify_release.py --package dist/RagnaCustomsApi.rmod
```

Install through RagnaModManager:

```bash
python3 scripts/install_rmod.py \
  --package dist/RagnaCustomsApi.rmod \
  --manager-cli "/path/to/RagnaModManager" \
  --game-dir "/path/to/steamapps/common/Ragnarock"
```

Use the standalone checker to separate manager deployment from UE4SS runtime availability:

```bash
python3 scripts/check_install.py --game-dir "/path/to/steamapps/common/Ragnarock"
python3 scripts/check_install.py --game-dir "/path/to/steamapps/common/Ragnarock" --source-root .
```

Run the complete offline verification suite:

```bash
python3 scripts/run_checks.py
```

Add `--game-dir "/path/to/steamapps/common/Ragnarock"` to also verify the installed copy and UE4SS install state. Add `--live` to probe the live RagnaCustoms API endpoints.

Expected complete state:

```text
win64_dir: yes
ue4ss_present: yes
manager_mods_layout: yes
mods_txt: yes
mod_enabled: yes
main_lua: yes
api_lua: yes
installed_current: yes
```

If `ue4ss_present` is `no`, the mod can be installed and enabled in `Mods/mods.txt`, but Ragnarock will not execute UE4SS Lua mods yet. Install UE4SS into `Ragnarock/Ragnarock/Binaries/Win64` first, then launch the game and check `UE4SS.log` for:

```text
[RagnaCustomsApi] loaded 0.2.0
```

Or run:

```bash
python3 scripts/check_runtime_log.py --game-dir "/path/to/steamapps/common/Ragnarock"
```

The runtime checker also accepts the diagnostic marker written by the mod after `main.lua` successfully loads the library:

```text
Ragnarock/Binaries/Win64/ue4ss/Mods/RagnaCustomsApi/Scripts/RagnaCustomsApi.loaded
Ragnarock/Binaries/Win64/Mods/RagnaCustomsApi/Scripts/RagnaCustomsApi.loaded
```
