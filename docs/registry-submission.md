# Registry submission checklist

Maintainers use this checklist when submitting a published `.rmod` to the mod registry. It is not consumed by the runtime or package.

After publishing a GitHub Release, fill in:

- Source repository: `https://github.com/Brollyy/RagnaCustomsApi`
- Author: `Brollyy`
- Release tag: `v<version>`
- Package URL: `https://github.com/Brollyy/RagnaCustomsApi/releases/download/v<version>/RagnaCustomsApi.rmod`
- SHA-256: `<64 lowercase hexadecimal characters>`
- Tested game / UE4SS versions: `<fill in>`
- Dependencies: none
- Permissions: UE4SS Lua; configured RagnaCustoms API and optional local song-folder access

The registry maintainer must review and merge the catalog entry before the manager treats the mod as official.
