# Current player signer

> Provenance notice carried over from iDuanJu
> (`STV/Resources/Licenses/HGCurrentPlayer-NOTICE.md`, GPL-3.0 project; the
> KS/custom transform itself is Apache-2.0, see below). It covers the
> `current*.go` / `HGCurrentPlayer.swift` / `HGCurrentProfile.swift` transform
> lineage only — not `SpadeKey.swift` (spade) or the rest of the signing code,
> which are GPL-3.0 iDuanJu code (see `THIRD_PARTY_NOTICES.md`).

`current*.go` ports the locally verified 7.2.1.33 arithmetic into the production
Go player. Its envelope was also accepted for a real 7.4.5.32
playback request and, independently, freshly registered anonymous Go requests.
It does not load APK/ELF files or reuse a phone identity, SDK token or captured
protobuf at runtime. Category requests retain their separate 551 signer.

The KS/custom transform candidate originated in OpenHongguo, commit
`05aa580a2fa914becabc5ae4be5b05539c66bda6`, under Apache-2.0. A copy of the license
is included in `HGCurrentPlayer-Apache-2.0.txt` (this directory; the upstream
`LICENSE.current.txt` filename does not exist in this repository). The
implementation was modified and checked against local native evidence: current
four-branch tables, initialization, bit-lane envelope, prefix, checksum, license
profile and explicit request binding. The factor compression implements six
independently verified selectors; the request builder searches a bounded ticket
range and signs the exact final bytes.

Constant provenance: `libmetasec_ml.so` SHA-256
`712384bd0e310fded0ae9b6441c2a264dd356dfaf1ef42d2ebc3c790fdd9269c`;
APK SHA-256 `0ed1bf1550ddd8bccfd78377c2222b3fd4c4646f167189ee91bc7cffc19c1984`.
Test fixtures contain synthetic native vectors and output digests only, with no
captured device credentials. This notice grants no license to third-party APKs
or services and does not guarantee future server acceptance.

## RedDuoDuo modifications

- The app bundle ships the complete compliance set as resources: the root
  `LICENSE`, `THIRD_PARTY_NOTICES.md` and every text in `Licenses/` (flattened
  into the bundle root by the resources build phase).
- The Apache-2.0 license text is included as `HGCurrentPlayer-Apache-2.0.txt`
  (this directory).
- The separate 551 category signer mentioned above (`HGPlayerSign.playbackHeaders`)
  is not included; only the current dialect (`HGCurrentPlayer.sign`) and the
  search dialect (`HGPlayerSign.signPOST`) remain.
- `HGCurrentPlayer.swift` / `HGCurrentProfile.swift` carry attribution and
  modification headers; see `THIRD_PARTY_NOTICES.md` for the full file list.
