# Future signed releases

Local builds are ad-hoc signed by `scripts/build_app.sh`. They are not notarized and must not be presented as an official distributable release. macOS does not launch an ad-hoc signed `SMAppService` root daemon, so Closed-Lid remains unavailable and the app reports that limitation without invoking Touch ID. When `CODESIGN_IDENTITY` names a Developer ID Application identity, the build script signs both executables with hardened runtime and the daemon uses the stable app identifier plus Apple Team ID requirement.

For a future public/private downloadable release:

1. enroll in the Apple Developer Program and create a Developer ID Application certificate;
2. define least-privilege entitlements and enable hardened runtime;
3. build an archive in a clean CI runner with a pinned Xcode version;
4. sign the complete bundle with Developer ID;
5. submit a zip or disk image with `notarytool` using CI-stored credentials;
6. staple and verify the notarization ticket;
7. publish checksums, source commit, supported macOS/Codex matrix, and release notes;
8. attach the verified artifact to a GitHub release only after tests, real read-only protocol handshake, and manual multi-client assertion verification pass.

For a notarized distribution, test the existing `SMAppService.daemon(plistName:)` bundle layout and approval flow with the real Developer ID identity, including disabled-background-item behavior, and retain the same narrow XPC/lease boundary. Do not claim that an ad-hoc local build supports privileged ServiceManagement deployment.

Never commit certificates, private keys, App Store Connect credentials, keychain exports, API keys, or notarization profiles. The current repository intentionally contains no publishing credentials or fake notarization step.
