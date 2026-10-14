///|
fn tar_failure(bytes : Bytes) -> String {
  try {
    ignore(decode_tar_pack(bytes))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
fn tar_rechecksum(bytes : Array[Byte]) -> Unit {
  for at in 148..<156 {
    bytes[at] = b' '
  }
  let mut sum = 0
  for at in 0..<512 {
    sum += bytes[at].to_int()
  }
  tar_write_octal(bytes, 148, 7, sum)
  bytes[155] = b' '
}

///|
test "USTAR refuses checksums extensions links header garbage numeric overflow and hidden trailers" {
  let bytes = zip_fixture().tar_pack()
  let checksum = bytes.to_array()
  checksum[0] = b'X'
  assert_eq(tar_failure(Bytes::from_array(checksum[:])), "TarProfile")
  for
    (at, byte) in [
      (156, b'1'),
      (156, b'2'),
      (156, b'5'),
      (156, b'x'),
      (156, b'g'),
      (156, b'S'),
      (257, b'X'),
      (263, b'1'),
      (157, b'X'),
      (500, b'X'),
      (124, b'\x80'),
      (124, b'-'),
      (124, b'9'),
      (329, b'1'),
      (11, b'X'),
    ] {
    let copy = bytes.to_array()
    copy[at] = byte
    tar_rechecksum(copy)
    assert_eq(tar_failure(Bytes::from_array(copy[:])), "TarProfile")
  }
  let huge = bytes.to_array()
  for at in 124..<136 {
    huge[at] = b'7'
  }
  tar_rechecksum(huge)
  assert_eq(tar_failure(Bytes::from_array(huge[:])), "TarProfile")
  let hidden = bytes.to_array()
  hidden[hidden.length() - 1] = b'X'
  assert_eq(tar_failure(Bytes::from_array(hidden[:])), "TarProfile")
  assert_eq(decode_tar_pack(bytes).encode(), zip_fixture().encode())
}

///|
test "USTAR whole-block sizes zero tails and prefix paths preserve all payload bytes" {
  for size in [0, 1, 511, 512, 513] {
    let payload = Bytes::make(size, b'x')
    let bytes = tar_write(
      [{ name: "job/report.xml", data: payload, }],
      16777216,
    )
    let entries = tar_entries(bytes, @ledger.Limits::default(), 16777216)
    assert_eq(entries.length(), 1)
    assert_eq(entries[0].data, payload)
    assert_eq(entries[0].name, "job/report.xml")
    if size % 512 != 0 {
      let bad_padding = bytes.to_array()
      bad_padding[512 + size] = b'x'
      assert_eq(tar_failure(Bytes::from_array(bad_padding[:])), "TarProfile")
    }
    let padded = bytes.to_array()
    padded.append(Array::make(512, b'\x00'))
    assert_eq(
      tar_entries(
        Bytes::from_array(padded[:]),
        @ledger.Limits::default(),
        16777216,
      )[0].data,
      payload,
    )
  }
  let prefixed = tar_write([{ name: "report.xml", data: b"xml", }], 16777216).to_array()
  tar_write_string(prefixed, 345, "job")
  tar_rechecksum(prefixed)
  assert_eq(
    tar_entries(
      Bytes::from_array(prefixed[:]),
      @ledger.Limits::default(),
      16777216,
    )[0].name,
    "job/report.xml",
  )
}

///|
test "USTAR closed packs refuse duplicate extra corrupt missing and malformed UTF8 members" {
  let evidence = zip_fixture()
  let entries = carrier_pack(evidence, @ledger.Limits::default())
  let original = evidence.encode()
  let duplicated = [entries[0], entries[0], entries[1]]
  assert_eq(tar_failure(tar_write(duplicated, 16777216)), "TarProfile")
  assert_eq(tar_failure(tar_write([entries[0]], 16777216)), "MissingPackFile")
  assert_eq(
    tar_failure(
      tar_write([..entries, { name: "extra.xml", data: b"unused", }], 16777216),
    ),
    "UnexpectedPackFile",
  )
  assert_eq(
    tar_failure(
      tar_write([entries[0], { ..entries[1], data: b"changed", }], 16777216),
    ),
    "IntegrityMismatch",
  )
  assert_eq(
    tar_failure(tar_write([{ name: "index.json", data: b"\xff", }], 16777216)),
    "InvalidUtf8",
  )
  assert_eq(tar_failure(tar_write([], 16777216)), "MissingPackFile")
  assert_eq(decode_tar_pack(evidence.tar_pack()).encode(), original)
}
