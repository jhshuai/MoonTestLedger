# Evidence transport profiles

ZIP carries the existing sealed file pack: `index.json` and exactly its content-addressed XML members. It preserves the full expected plan and recovery policy. Absent expected reports remain incomplete; missing accepted XML, extra members and changed content are invalid. No general filesystem extraction or archive-conversion API is exported.

```text
moon run scripts/render-demo.mbtx wasm
moon run --target wasm cmd/moontestledger -- zip-pack output/jest-evidence.json output/jest.zip
moon run --target wasm cmd/moontestledger -- restore-zip output/jest.zip
moon run --target wasm cmd/moontestledger -- verify-zip output/jest.zip
```

Use a new destination; overwrite is refused. Creation/restore return 0. The real six-test Jest verification returns 1 (four failures); verification preserves the original 0/1/3 gate. Invalid input returns 2 with JSON diagnostics on stderr. Native accepts the same commands. CLI binary reads are capped at 16 MiB. Library `Evidence.zip_pack(limits~, max_bytes~)` / `decode_zip_pack(bytes, limits~, max_bytes~)` default to 16 MiB and allow a positive cap up to 256 MiB. Existing source/plan/JSON budgets still apply.

The initial ZIP profile accepts classic single-disk ZIP, STORED/DEFLATE, ASCII portable relative names, UTF-8 marker, compression hints and signed/unsigned classic data descriptors. It requires matching local/central records, exact expanded sizes, CRC-32, contiguous nonoverlapping local records and a closed pack inventory. Before expansion, per-member bytes are capped at four times `max_source_units`, aggregate bytes at four times `max_total_source_units + max_source_units`, and count at `max_reports + 1`. Index and XML decoding are strict UTF-8. Index validation precedes XML expansion; SHA-256 receipts and complete XML replay follow container checks.

Encryption, ZIP64, split archives, extra fields, comments, links, directory entries, special files, executable prefixes, gaps and hidden records are refused. This constrained profile does not accept arbitrary GitHub artifact ZIPs. Timestamps/permissions are carrier metadata rather than test evidence: exports use fixed zero timestamp and no filesystem attributes; restore returns evidence, not reconstructed filesystem metadata. No signing, sender authentication, compression performance or hostile-filesystem transaction claim is made. Trust the index independently where required.

Compression, decompression and CRC reuse [hustcer/fzip 0.8.8](https://github.com/hustcer/fzip), Apache-2.0. Container guards, evidence adapters and tests are project-authored Apache-2.0. [PKWARE APPNOTE 6.3.10](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) is a format reference, not redistributed text. [GitHub artifact download API](https://docs.github.com/en/rest/actions/artifacts#download-an-artifact) documents the ZIP delivery workflow. The real XML retains its MIT notice.
