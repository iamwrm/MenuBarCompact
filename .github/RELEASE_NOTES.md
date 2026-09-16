Download the **macOS-arm64.zip** asset below, unzip it, and copy **MenuBarCompact.app** to `/Applications`. Requires **macOS 27 and Apple Silicon**. The matching `.sha256` file can be used to verify the download.

Built from this tag by GitHub Actions. No Apple signing certificate or notarization is used; macOS may require manual approval on first launch. The arm64 linker may add an ad-hoc code seal, which is not a developer signature. Accessibility permission may need to be granted again when replacing a differently signed build.

The app uses a private macOS API and remains experimental. The iStat compatibility utility requires developer-tools Python at `/usr/bin/python3`; see the README for requirements and setup.
