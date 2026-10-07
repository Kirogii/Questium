# Quest build and signing

The Quest VR APK workflow checks out all submodules, installs Java 21, downloads checksum-verified Godot 4.6, imports the checked-in `xr` project, tests the VR scripts, installs Android platform 37/build-tools 36/CMake and Linux native build dependencies, and builds an arm64 no-MTL APK. The Godot Android runtime and OpenXR loader are Gradle dependencies; the licensed Meta AAR and desktop GDExtension libraries are included in the repository. A Godot installation folder, local SDK, generated `.godot` cache and generated `vr.pck` are not committed.

Configure these **repository Actions secrets**:

| Secret / signing environment variable | Value |
| --- | --- |
| `VR_SIGNING_KEYSTORE_BASE64` | Base64-encoded private JKS/PKCS12 keystore |
| `VR_SIGNING_STORE_PASSWORD` | Keystore password |
| `VR_SIGNING_KEY_PASSWORD` | Private-key password |
| `VR_SIGNING_KEY_ALIAS` | Signing alias |

Trusted branch/tag/manual runs sign with `apksigner`, verify the signature and upload the APK plus SHA256 checksum. Pull requests only produce a debug-signed validation artifact and never receive signing secrets. Private keys stay outside Git; retain an offline backup because Android updates must use the same certificate.

Pushing tag `v1` publishes the prerelease named `alpha`; the inherited upstream release workflow skips that tag. Run **Quest VR APK** manually to build another signed artifact without publishing. The alpha APK retains the no-MTL debug application ID and development flags.
