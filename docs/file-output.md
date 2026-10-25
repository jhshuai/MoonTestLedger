# Safe evidence files

Evidence creation commands accept one trailing `--output NEW.json`: `archive`, `collect`, `collect-zip`, `collect-tar`, `merge`, `retry` and `append`. All input validation and serialization finish before creating the output. The destination is created exclusively, encoded as UTF-8 without BOM and terminated by one newline. Existing files/directories and missing parents are refused; no parent directories are created. On successful file output stdout is empty. Omit the option to preserve the original stdout behavior byte-for-byte.

```text
moon run --target wasm cmd/moontestledger -- collect examples/upstream/collection.json examples/upstream --output jest.json
moon run --target wasm cmd/moontestledger -- verify jest.json
```

Creation returns 0 for valid complete, failing or incomplete evidence. `verify` returns the original gate: 0 passing, 1 adverse result or denied recovery, 3 incomplete, 2 invalid input. The real Jest example verifies at 1. Writing to an existing input path returns `OutputWrite` with exit 2 and preserves that file. Other unsupported option placements/commands return a usage diagnostic. Paths named exactly `--output` are reserved command syntax.

This avoids shell-dependent text redirection encodings and accidental input truncation. Failed writes attempt to remove only the file created by that operation. This is not transactional protection against hostile concurrent filesystem changes or a guarantee of recovery after process termination. CLI support remains Wasm/native; library APIs are unchanged.

`moon run scripts/output-e2e.mbtx wasm` (or `native`) runs actual CLI processes for all seven commands, real upstream XML, Unicode paths, exact output, no overwrite, invalid input before file creation, missing evidence, denied recovery, missing parents and correction after error. The integrated verifier includes these checks and an explicit strict `moon build` for every target.
