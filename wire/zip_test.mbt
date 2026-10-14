///|
test "ZIP round trip preserves full XML inventory gate policy and deterministic bytes" {
  for missing in [false, true] {
    for deny in [false, true] {
      let evidence = @wire.decode_evidence(
        @wire.encode_evidence(archive_ledger(missing~), deny_recovered=deny),
      )
      let bytes = evidence.zip_pack() catch {
        @ledger.InputError::Invalid(d) => fail(d.code + ": " + d.message)
      }
      assert_eq(evidence.zip_pack(), bytes)
      let restored = @wire.decode_zip_pack(bytes) catch {
        @ledger.InputError::Invalid(d) => fail(d.code + ": " + d.message)
      }
      assert_eq(restored.encode(), evidence.encode())
      assert_eq(restored.exit_code(), evidence.exit_code())
      assert_eq(restored.zip_pack(), bytes)
    }
  }
}

///|
test "ZIP budgets truncation corruption and recovery leave evidence unchanged" {
  let evidence = @wire.decode_evidence(@wire.encode_evidence(archive_ledger()))
  let before = evidence.encode()
  let bytes = evidence.zip_pack()
  for length in [0, 1, 21, bytes.length() - 1] {
    assert_true(
      (try @wire.decode_zip_pack(bytes[:length].to_owned()) catch {
        _ => None
      } noraise {
        _ => Some(())
      })
      is None,
    )
  }
  for maximum in [0, -1, bytes.length() - 1, 268435457] {
    assert_true(
      (try evidence.zip_pack(max_bytes=maximum) catch {
        _ => None
      } noraise {
        _ => Some(())
      })
      is None,
    )
  }
  assert_eq(
    @wire.decode_zip_pack(bytes, max_bytes=bytes.length()).encode(),
    before,
  )
  let changed = bytes.to_array()
  changed[0] = b'X'
  assert_true(
    (try @wire.decode_zip_pack(Bytes::from_array(changed[:])) catch {
      _ => None
    } noraise {
      _ => Some(())
    })
    is None,
  )
  assert_eq(evidence.encode(), before)
  assert_eq(@wire.decode_zip_pack(bytes).encode(), before)
}
