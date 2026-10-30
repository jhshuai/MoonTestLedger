///|
test "generated workload checks exact case classes across decade boundaries" {
  for
    (count, failed, skipped) in [
      (1, 1, 0),
      (2, 1, 1),
      (9, 1, 1),
      (10, 1, 1),
      (11, 2, 1),
    ] {
    guard measure(count)
      is {
        "cases": Number(actual, ..),
        "failure_cases": Number(failures, ..),
        "skipped_cases": Number(skips, ..),
        "checks_passed": True,
        ..
      } else {
      fail("Expected checked workload")
    }
    assert_eq(actual, count.to_double())
    assert_eq(failures, failed.to_double())
    assert_eq(skips, skipped.to_double())
  }
}

///|
test "workload size refusal recovers and source digests are deterministic" {
  for count in [0, -1, 100001] {
    assert_true(
      try {
        ignore(measure(count))
        false
      } catch {
        _ => true
      },
    )
  }
  guard measure(2) is { "xml_sha256": xml, "archive_sha256": archive, .. } else {
    fail("Expected digests")
  }
  guard measure(2)
    is { "xml_sha256": again_xml, "archive_sha256": again_archive, .. } else {
    fail("Expected digests")
  }
  assert_eq(xml, again_xml)
  assert_eq(archive, again_archive)
}
