///|
test "fractional JSON lexemes cannot become schema versions or attempts by rounding" {
  for
    value in [
      "1.0000000000000001", "0.99999999999999999", "2147483647.00000001", "10000000000000001e-16",
      "214748364700000001e-8", "1e-999999999999999999999999",
    ] {
    assert_eq(plan_error(plan_source(schema=value)).code, "ExpectedInteger")
    assert_eq(
      bundle_error(bundle_source(attempt=value)).code,
      "ExpectedInteger",
    )
  }
  let escaped_key = bundle_source().replace(
    old="\"attempt\":1",
    new="\"\\u0061ttempt\":1.0000000000000001",
  )
  assert_eq(bundle_error(escaped_key).code, "ExpectedInteger")
}

///|
test "exact decimal and exponent integers preserve the supported numeric contract" {
  for
    (source, expected) in [
      ("1.0", 1),
      ("1e0", 1),
      ("10e-1", 1),
      ("100.0e-2", 1),
      ("0.1e1", 1),
      ("0.00000000000001e14", 1),
      ("2.147483647e9", 2147483647),
      ("21474836470e-1", 2147483647),
      ("1e9", 1000000000),
      ("9999999990e-1", 999999999),
    ] {
    assert_eq(
      @wire.decode_bundle(bundle_source(attempt=source)).documents[0].binding.attempt,
      expected,
    )
  }
  for
    source in [
      "1e10", "2.147483648e9", "10e-2", "1e999999999999999999999999", "-0", "0.0",
    ] {
    assert_eq(
      bundle_error(bundle_source(attempt=source)).code,
      "ExpectedInteger",
    )
  }
  assert_eq(
    @wire.decode_plan(plan_source(schema="100.0e-2")).reports[0].attempt,
    1,
  )
}
