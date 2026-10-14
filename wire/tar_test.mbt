///|
test "USTAR round trip preserves full original XML inventory policy gate and deterministic bytes" {
  for missing in [false, true] {
    for deny in [false, true] {
      let evidence = @wire.decode_evidence(
        @wire.encode_evidence(archive_ledger(missing~), deny_recovered=deny),
      )
      let bytes = evidence.tar_pack()
      assert_eq(evidence.tar_pack(), bytes)
      let restored = @wire.decode_tar_pack(bytes)
      assert_eq(restored.encode(), evidence.encode())
      assert_eq(restored.exit_code(), evidence.exit_code())
      assert_eq(restored.tar_pack(), bytes)
    }
  }
}

///|
test "USTAR inclusive binary budgets invalid budgets truncation and recovery" {
  let evidence = @wire.decode_evidence(@wire.encode_evidence(archive_ledger()))
  let before = evidence.encode()
  let bytes = evidence.tar_pack()
  for maximum in [0, -1, bytes.length() - 1, 268435457] {
    assert_true(
      (try evidence.tar_pack(max_bytes=maximum) catch {
        _ => None
      } noraise {
        _ => Some(())
      })
      is None,
    )
  }
  assert_eq(
    @wire.decode_tar_pack(bytes, max_bytes=bytes.length()).encode(),
    before,
  )
  for length in [0, 1, 511, 512, bytes.length() - 1, bytes.length() - 512] {
    assert_true(
      (try @wire.decode_tar_pack(bytes[:length].to_owned()) catch {
        _ => None
      } noraise {
        _ => Some(())
      })
      is None,
    )
  }
  assert_eq(@wire.decode_tar_pack(bytes).encode(), before)
  assert_eq(evidence.encode(), before)
}
