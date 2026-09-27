# Releasing ContainerManager

ContainerManager updates itself with [Sparkle](https://sparkle-project.org). Each GitHub release carries two assets the app depends on:

- `ContainerManager.dmg`: the notarized app. The README links to `releases/latest/download/ContainerManager.dmg`, so keep the name.
- `appcast.xml`: Sparkle's feed. The app reads `releases/latest/download/appcast.xml` (`SUFeedURL` in `Info.plist`), so an update is only announced once the release that carries it is published.

## One-time setup

Sparkle checks each update against an EdDSA public key built into the app.

1. Resolve packages in Xcode, then run Sparkle's `generate_keys`:

   ```bash
   "$(find ~/Library/Developer/Xcode/DerivedData -path '*/artifacts/sparkle/Sparkle/bin/generate_keys' -print -quit)"
   ```

   The private key goes into your login keychain. Back it up (`generate_keys -x private-key-file`) somewhere safe: without it you can't ship an update that existing copies of the app will accept.
2. Add the public key it prints to `Info.plist` as `SUPublicEDKey` (a string).

Until that key is in `Info.plist`, the app reports that it isn't set up to update itself.

## Each release

1. **Bump the build number.** Raise `CURRENT_PROJECT_VERSION` (project level), and `MARKETING_VERSION` as usual. Sparkle compares build numbers, so an unchanged one is never offered as an update. The privileged helper shares these numbers, and the app uses the build number to notice a stale helper.
2. **Archive and notarize** as before: Product ▸ Archive, Distribute App ▸ Direct Distribution. Check that the archive is a macOS App archive, not a Generic Xcode Archive; the helper target's `SKIP_INSTALL = YES` is what ensures this. Package the exported app as `ContainerManager.dmg`, then notarize and staple it.
3. **Verify** the exported app:

   ```bash
   codesign --verify --deep --strict --verbose=2 ContainerManager.app
   spctl -a -vv ContainerManager.app
   xcrun stapler validate ContainerManager.dmg
   ```

4. **Write the feed:**

   ```bash
   scripts/make-appcast.sh path/to/ContainerManager.dmg
   ```

   This reads the version and build from the app inside the DMG, signs the DMG with your key, and writes `appcast.xml` next to it, pointing at the `v<version>` tag.
5. **Publish** a GitHub release tagged `v<version>` with both `ContainerManager.dmg` and `appcast.xml` attached.

## Testing an update locally

Debug builds can read a local feed instead:

```bash
defaults write com.bartreardon.ContainerManager debugAppcastURL http://localhost:8000/appcast.xml
```

Serve a folder containing a higher-build DMG and its appcast (for example with `python3 -m http.server 8000`), with the enclosure URL edited to point at it. Remove the setting afterwards with `defaults delete com.bartreardon.ContainerManager debugAppcastURL`.

## The privileged helper

`ContainerManagerHelper` is embedded in the app at `Contents/MacOS` and registered with `SMAppService` from `Contents/Library/LaunchDaemons/com.bartreardon.ContainerManager.Helper.plist`. It ships inside the app, so a Sparkle update brings a new helper with it. The helper exits after a minute idle, and the app re-registers it if its build or path doesn't match.

Release builds of the helper accept only the Developer ID-signed app, and the app accepts only the Developer ID-signed helper. A Debug build can't talk to a released helper, or the other way round. When switching between the two, disable the helper in Settings first. `sfltool dumpbtm` lists what's registered.
