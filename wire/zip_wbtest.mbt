///|
fn zip_fixture() -> Evidence raise @ledger.InputError {
  let plan = @ledger.RunPlan::new("zip-run", "rev", [
    {
      id: "one",
      environment: "linux",
      shard: "s",
      attempt: 1,
      cases: [{ classname: "c", name: "n", }],
    },
  ])
  let ledger = @ledger.Ledger::new(plan)
  ledger.ingest({
    binding: {
      id: "one",
      run_id: "zip-run",
      revision: "rev",
      environment: "linux",
      shard: "s",
      attempt: 1,
    },
    report: @junit.parse(
      "<testsuite><testcase classname=\"c\" name=\"n\"/></testsuite>",
    ),
  })
  decode_evidence(encode_evidence(ledger))
}

///|
fn zip_failure(
  bytes : Bytes,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(decode_zip_pack(bytes, limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
fn zip_set32(bytes : Array[Byte], at : Int32, value : UInt32) -> Unit {
  for i in 0..<4 {
    bytes[at + i] = (value >> (i * 8)).to_byte()
  }
}

///|
test "ZIP refuses unsupported flags types metadata inconsistent records oversized expansion and corrupt CRC" {
  let evidence = zip_fixture()
  let bytes = evidence.zip_pack()
  let cd = zip_number(bytes, bytes.length() - 6)
  for
    (at, value) in [
      (cd, b'X'),
      (cd + 8, b'\x01'),
      (cd + 10, b'\x09'),
      (cd + 30, b'\x01'),
      (cd + 32, b'\x01'),
      (cd + 34, b'\x01'),
      (cd + 38, b'\x10'),
      (cd + 41, b'\xa0'),
      (cd + 42, b'\x01'),
      (6, b'\x01'),
      (26, b'\x01'),
      (28, b'\x01'),
      (30, b'X'),
      (14, b'X'),
    ] {
    let copy = bytes.to_array()
    copy[at] = value
    assert_eq(zip_failure(Bytes::from_array(copy[:])), "ZipProfile")
  }
  let oversized = bytes.to_array()
  zip_set32(oversized, cd + 24, 16777217U)
  assert_eq(zip_failure(Bytes::from_array(oversized[:])), "SourceLimit")
  let crc = bytes.to_array()
  zip_set32(crc, cd + 16, 0U)
  zip_set32(crc, 14, 0U)
  assert_eq(zip_failure(Bytes::from_array(crc[:])), "ZipProfile")
  assert_eq(decode_zip_pack(bytes).encode(), evidence.encode())
}

///|
test "ZIP stored payload malformed UTF8 duplicates and closed inventory are rejected" {
  let evidence = zip_fixture()
  let entries = carrier_pack(evidence, @ledger.Limits::default())
  let options = { ..@fzip.ZipEntryOptions::default(), level: 0, }
  let stored = Bytes::from_array(
    @fzip.zip_sync_checked(
      entries.map(entry => (entry.name, entry.data.to_fixedarray())),
      opts=options,
    )[:],
  )
  assert_eq(decode_zip_pack(stored).encode(), evidence.encode())
  for
    extra in [
      ("other.txt", @utf8.encode("extra").to_fixedarray()),
      (entries[0].name, entries[0].data.to_fixedarray()),
    ] {
    let pairs = entries.map(entry => (entry.name, entry.data.to_fixedarray()))
    pairs.push(extra)
    assert_eq(
      zip_failure(
        Bytes::from_array(@fzip.zip_sync_checked(pairs, opts=options)[:]),
      ),
      "ZipProfile",
    )
  }
  let invalid = @fzip.zip_sync_checked(
    [("index.json", FixedArray::make(1, b'\xff'))],
    opts=options,
  )
  assert_eq(zip_failure(Bytes::from_array(invalid[:])), "InvalidUtf8")
  let empty = @fzip.zip_sync_checked([], opts=options)
  assert_eq(zip_failure(Bytes::from_array(empty[:])), "MissingPackFile")
}

///|
test "ZIP signed and unsigned classic data descriptors are accepted and checked" {
  let original = zip_fixture().zip_pack()
  let cd = zip_number(original, original.length() - 6)
  let first = zip_entries(original, @ledger.Limits::default(), 16777216)[0]
  for signed in [false, true] {
    let descriptor : Array[Byte] = []
    if signed {
      descriptor.append([b'P', b'K', b'\x07', b'\x08'])
    }
    for
      value in [
        first.crc,
        first.compressed.reinterpret_as_uint(),
        first.expanded.reinterpret_as_uint(),
      ] {
      for i in 0..<4 {
        descriptor.push((value >> (8 * i)).to_byte())
      }
    }
    let bytes = original[:first.end].to_owned().to_array()
    bytes.append(descriptor)
    bytes.append(original[first.end:].to_owned().to_array())
    bytes[6] = b'\x08'
    let shifted_cd = cd + descriptor.length()
    bytes[shifted_cd + 8] = b'\x08'
    let next_cd = shifted_cd + 46 + zip_u16(original, cd + 28)
    zip_set32(
      bytes,
      next_cd + 42,
      first.end.reinterpret_as_uint() +
      descriptor.length().reinterpret_as_uint(),
    )
    zip_set32(bytes, bytes.length() - 6, shifted_cd.reinterpret_as_uint())
    let valid = Bytes::from_array(bytes[:])
    assert_eq(decode_zip_pack(valid).encode(), zip_fixture().encode())
    bytes[first.end + descriptor.length() - 1] = b'\xff'
    assert_eq(zip_failure(Bytes::from_array(bytes[:])), "ZipProfile")
  }
}
