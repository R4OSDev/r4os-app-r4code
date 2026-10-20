# R4CODE.R4X

`R4CODE.R4X` is an independent R4OS application implemented in Zig.

## Package

- Version: `0.1.7`
- Image target: `/SOFTWARE/R4CODE/R4CODE.R4X`
- Image scope: `full`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

## Build

On Windows:

    Build.bat

On Linux or macOS:

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

TextArea computes visible rows and caret/scroll extents in one bounded
layout pass. The editor delegates edit visibility to that shared owner,
including one explicit update after a clipboard cut.

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.

Unicode dialog contract (0.85.43)
--------------------------------
Save-as fields accept complete Unicode scalar events and keep separate byte
cursor/selection positions. Invalid or overlong preloads and failed insertions
preserve the previous input; a rejected filename cannot be saved until edited
or replaced by a valid selection. Initial path arguments and constructed paths
are checked in full, before copying or filesystem access. Directory labels may
show a whole-scalar prefix plus ...; the stored full path alone identifies a row.
Glyph coverage is independent of text input. No normalization, grapheme, Bidi
or shaping promise follows from these scalar operations.
Build.sh test (Build.bat test on Windows) exercises the actual app dialog owner.
Tests/DialogText is an explicit IMAGE_SCOPE=none console fixture of the same app
source. /DIALOGTEST additionally verifies real private file saves, full Unicode
row identity, failure-state preservation and cleanup; Notepad checks actual
search values too. It does not claim a manual visual GUI acceptance.
Save and Save As use the existing SDK document_save.Saver. The old target is
never passed to fileWrite; path/Dirty change only after confirmed publication.
Unconfirmed storage publication retains complete recovery copies and edited
input. A truncated source may be saved only to a missing target.

0.85.44: Rebuilt with SDK0.64.57 and the shared R4STD Unicode17.0.0
extended grapheme editing boundaries. Byte offsets, scalar font advances
and grapheme clusters are distinct; no shaping or BiDi support is implied.
