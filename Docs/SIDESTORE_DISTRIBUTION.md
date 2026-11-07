# SideStore distribution setup

GlassType now has a CI path for building an unsigned iOS IPA and, optionally, publishing that IPA and AltSource metadata from the private source repository to a separate public distribution repository. The public repository must never receive the source tree or its commit history.

## Project facts and packaging choice

- The project is `GlassType.xcodeproj` (no `.xcworkspace`) with the `GlassType` scheme and Debug/Release configurations.
- Swift Package tools version is 5.9; the package minimum is iOS 16. The Xcode targets also set iOS 16 as deployment target.
- App bundle ID: `org.opentype.GlassType`. Keyboard Extension bundle ID: `org.opentype.GlassType.Keyboard`.
- The app embeds `GlassTypeKeyboard.appex` in `PlugIns/` through the Xcode Embed App Extensions copy phase. The extension point is `com.apple.keyboard-service`.
- App and extension entitlements both use `group.org.opentype.GlassType`. The extension plist requests Full Access, while basic typing remains available without it.
- App and extension versions come from their `Info.plist` files. The committed version is the development baseline; CI sets temporary versions in its checkout before archiving.
- The AppIcon asset catalog supplies light and dark variants. The distribution repo receives a single PNG icon copied from the light appearance.
- `Scripts/make-unsigned-ipa.sh` archives the device app without an Apple distribution certificate, checks the embedded keyboard and packaged dictionaries, and zips the `Payload` directory. SideStore is expected to re-sign this IPA.

The IPA check verifies both bundle IDs, matching version/build values, the keyboard extension point, app assets and bundled dictionaries. Because this is an unsigned archive, it cannot prove that SideStore will preserve and accept every entitlement after re-signing. That still needs the real-device installation check below.

## Repository layout and exposure boundary

Keep the current source repository private. Create a separate public repository, for example `GlassType-Distribution`, with its default branch named `main` and an initial commit. Its generated contents are limited to:

```text
sources/stable.json
sources/beta.json
releases/                 # GitHub Releases and IPA assets, not checked-in source
assets/icon.png
README.md
```

The workflow checks out private source only on a GitHub-hosted runner. The only files staged for the public commit are the selected AltSource JSON, icon and generated distribution README. The source code, tests, project, workflow and source history are not copied. The public repo name is configured outside the source in Actions Variables.

## GitHub Actions configuration

In the **private GlassType repository**, add:

1. Repository **Variable** `DISTRIBUTION_REPOSITORY` with value `owner/GlassType-Distribution` (use the real owner and repository name).
2. Fine-grained Personal Access Token as repository **Secret** `DISTRIBUTION_TOKEN`.

Create the token in GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens. Limit repository access to the one public distribution repository and grant only **Contents: Read and write**. Do not put the token in a file, workflow output, or build step. The build job has no distribution token; only the separate publication job receives it. Pull requests never run publication.

The distribution repo must already exist and have `main`; this workflow intentionally does not create or change GitHub repositories. If either Action setting is absent, compilation and the private workflow artifact still run and the publication job is skipped. If the repository variable is set but the token is missing or invalid, publication fails closed.

The existing `GITHUB_TOKEN` remains read-only. The distribution PAT is used only by the publication job to check out and commit the public metadata and create the release in the target repo. Do not grant it access to the private source repository.

## Channels and versions

- A pull request to `main` runs structural validation, XCTest and the simulator build. It does not archive or publish an IPA.
- A push to `main` builds a Beta IPA. CI derives a unique numeric app version from the committed major/minor version and the GitHub Actions run number, and uses the run number as `CFBundleVersion`.
- A `vX.Y.Z` tag builds Stable and requires the tag version to exactly match `CFBundleShortVersionString` inside the IPA.
- `workflow_dispatch` offers Beta and Stable. Beta can be manually dispatched from a branch. Stable dispatch must target the corresponding `vX.Y.Z` tag; attempting Stable from a branch fails before archive.
- Stable and Beta JSON files have distinct source identifiers but intentionally use the same application bundle identifier. SideStore does not guarantee that both channels can be installed as separate apps, or that switching from a higher Beta version to a lower Stable version will be treated as an update. Bump the next stable version above the beta line before promoting it.
- Every IPA release tag is unique (`beta-v<version>-b<build>` or the stable version tag). Existing tags/versions are never overwritten. AltSource keeps up to the latest 20 versions in newest-first order.

The unsigned IPA is uploaded as a private Actions artifact even when public distribution is not configured. A public release is created only after the IPA has passed the packaging checks and the new AltSource file validates against the vendored official SideStore schema snapshot in `Scripts/sidestore-source-schema.json` (downloaded from `SideStore/sidestore-source-types`). The snapshot SHA-256 is `e07838d7672da0f2dc920350759752121ad3cdeb7c7d58cd80996b936f767fc3`; update it deliberately when adopting an upstream schema change. The workflow uses the pinned `jsonschema` validator and checks that the direct asset URL is publicly downloadable before committing metadata.

## Installing and updating from SideStore

After the first successful public release, the generated public README provides the exact links. The source URLs follow this form:

```text
sidestore://source?url=https%3A%2F%2Fraw.githubusercontent.com%2FOWNER%2FREPOSITORY%2Fmain%2Fsources%2Fstable.json
sidestore://source?url=https%3A%2F%2Fraw.githubusercontent.com%2FOWNER%2FREPOSITORY%2Fmain%2Fsources%2Fbeta.json
```

Replace the placeholders with the configured public repository. Alternatively, add the raw JSON URL in SideStore → Sources → Add Source. Choose GlassType, install, and enable it in iOS Settings → General → Keyboard. Refresh SideStore to find future releases. During installation choose to keep/register the Keyboard Extension. Free Apple IDs remain subject to SideStore's app-ID and signing limits.

Both the raw source URL and the direct IPA release URL are checked by the publish workflow for public access. Those checks cannot be performed until the public repository exists and contains a release.

## Manual device acceptance

Before sharing a release with testers:

1. Download the IPA from the public Release and install it through SideStore on a supported iPhone.
2. Confirm GlassType and GlassTypeKeyboard appear in SideStore and that iOS can enable the keyboard.
3. Test English, Russian and Ukrainian layouts, symbols, emoji, suggestions, cursor control and secure text fields.
4. Confirm Refresh All detects the next build and updates the app while retaining the Keyboard Extension.
5. Check the Stable and Beta source separately. Do not assume both listings can coexist as installed apps.

Successful CI proves compilation and package structure only. It is not a substitute for SideStore re-signing and on-device use.

## Common setup failures

- **Publish job skipped:** `DISTRIBUTION_REPOSITORY` is unset. Add the `owner/repository` Actions Variable.
- **Checkout or release gets 404/403:** verify the target repo is public, the PAT is restricted to that repo, and Contents read/write is granted.
- **Cannot checkout `main`:** initialize the target repo and make `main` its default branch before running publication.
- **Stable version mismatch:** the source tag and both plist versions must use the same `X.Y.Z` value; rerun from the correct tag.
- **Tag/version already exists:** do not delete prior releases or reuse a version. Increase the version and create a new tag/build.
- **Source JSON URL is missing:** the first release has not completed, or the default branch/raw URL is not public. Check `sources/<channel>.json` on the target repo.
- **IPA installs but keyboard is absent:** confirm SideStore registered the embedded extension App ID and iOS keyboard settings list GlassType. Re-signing and entitlement behavior needs on-device diagnosis.
