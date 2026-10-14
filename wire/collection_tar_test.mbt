///|
test "public USTAR collection empty archive preserves declared reports and recovery policy" {
  for deny in [false, true] {
    let spec = collection_spec(deny~)
    let empty = Bytes::make(1024, b'\x00')
    let evidence = spec.collect_tar(empty)
    assert_eq(evidence.encode(), spec.collect([][:]).encode())
    assert_eq(evidence.exit_code(), 3)
    assert_eq(evidence.deny_recovered(), deny)
    assert_eq(evidence.snapshot().plan.reports.length(), 2)
  }
}

///|
test "public USTAR collection rejects truncated transport and unsafe binary budgets then recovers" {
  let spec = collection_spec()
  let before = spec.encode()
  for length in [0, 1, 511, 512, 1023] {
    assert_true(
      (try spec.collect_tar(Bytes::make(length, b'\x00')) catch {
        _ => None
      } noraise {
        _ => Some(())
      })
      is None,
    )
  }
  for maximum in [0, -1, 1023, 268435457] {
    assert_true(
      (try
        spec.collect_tar(Bytes::make(1024, b'\x00'), max_bytes=maximum)
      catch {
        _ => None
      } noraise {
        _ => Some(())
      })
      is None,
    )
  }
  assert_eq(
    spec.collect_tar(Bytes::make(1024, b'\x00'), max_bytes=1024).exit_code(),
    3,
  )
  assert_eq(spec.encode(), before)
}
