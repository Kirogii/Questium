# Questium ARM64 decoder input

Windows Quest builds package `arm64-v8a/libimagedecoder2.so` directly. This is a durable build input, not a generated Gradle cache. Configuration verifies its pinned SHA-256 and AArch64 ELF header before registering Android build tasks. Quest APKs on this path support ARM64 only.

The binary was imported from the existing Questium workspace decoder output dated 2026-10-09. Its exported JNI functions match the current `ca.mpreg.imagedecoder.ImageDecoder` wrapper. The exact original toolchain and source-build attestation are unavailable; `manifest.json` records that limitation rather than inventing provenance. Preserve this distinction when replacing or redistributing this artifact.

The wrapper source, native dependency versions, download hashes, patches, and source-build recipes remain in `external/imagedecoder-houri`. Wrapper and available dependency notices accompany this input in `notices/`. Source builds remain available with `-Pquestium.decoder.fromSource=true`, using the native Linux build environment documented there. The Windows default does not configure that source build or call WSL.

Windows translation builds compile the fork's own llama JNI implementation with the Windows Android NDK/CMake toolchain, using CPU inference by default. Vulkan GPU offload remains an explicit optional build configuration; see `llamatik-native/BUILD.md`.
