# Resolving dll from nuget packages

## Excluded RIDs

The following RIDs are excluded from the build process to avoid unnecessary dependencies and to keep the build lightweight:
- uap10.0
- maccatalyst-x64
- maccatalyst-arm64
- linux-musl-x64
- linux-musl-arm64
- linux-musl-arm
- linux-musl-x86
- linux-musl-x86_64
- linux-musl-armv7
- linux-musl-armv6
- linux-musl-armv5
- linux-musl-armv8
- linux-musl-armv7l
- linux-musl-armv8l
- linux-musl-armv6l
- linux-armel
- linux-ppc64le
- linux-riscv64
