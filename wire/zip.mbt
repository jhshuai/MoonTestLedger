///|
fn zip_need(ok : Bool, message : String) -> Unit raise @ledger.InputError {
  if !ok {
    raise bad("ZipProfile", "$", message)
  }
}

///|
fn zip_u16(data : Bytes, at : Int32) -> Int32 {
  data[at].to_int() | (data[at + 1].to_int() << 8)
}

///|
fn zip_u32(data : Bytes, at : Int32) -> UInt32 {
  data[at].to_uint() |
  (data[at + 1].to_uint() << 8) |
  (data[at + 2].to_uint() << 16) |
  (data[at + 3].to_uint() << 24)
}

///|
fn zip_number(data : Bytes, at : Int32) -> Int32 raise @ledger.InputError {
  let value = zip_u32(data, at).to_int64()
  zip_need(
    value <= 268435456L,
    "ZIP64 or oversized offsets and lengths are unsupported",
  )
  value.to_int()
}

///|
priv struct ZipMember {
  name : String
  offset : Int32
  end : Int32
  start : Int32
  compressed : Int32
  expanded : Int32
  crc : UInt32
  compression : Int32
}

///|
// Validate every record before expansion. No filesystem extraction occurs.
fn zip_entries(
  data : Bytes,
  limits : @ledger.Limits,
  maximum : Int32,
) -> Array[ZipMember] raise @ledger.InputError {
  carrier_budget(data.length(), maximum)
  zip_need(data.length() >= 22, "Truncated ZIP end record")
  let end = data.length() - 22
  zip_need(
    zip_u32(data, end) == 0x06054b50U,
    "Expected uncommented classic ZIP end record",
  )
  zip_need(
    zip_u16(data, end + 4) == 0 &&
    zip_u16(data, end + 6) == 0 &&
    zip_u16(data, end + 20) == 0,
    "Split ZIP and archive comments are unsupported",
  )
  let count = zip_u16(data, end + 10)
  zip_need(
    count == zip_u16(data, end + 8) && count <= limits.max_reports + 1,
    "Inconsistent or excessive ZIP entry count",
  )
  let directory = zip_number(data, end + 16)
  zip_need(
    directory + zip_number(data, end + 12) == end,
    "Central directory must immediately precede the end record",
  )
  let entries : Array[ZipMember] = []
  let names : Set[String] = Set([])
  let mut cursor = directory
  let mut total = 0L
  for _ in 0..<count {
    zip_need(cursor >= 0 && cursor + 46 <= end, "Truncated central header")
    zip_need(zip_u32(data, cursor) == 0x02014b50U, "Invalid central signature")
    let flags = zip_u16(data, cursor + 8)
    let compression = zip_u16(data, cursor + 10)
    zip_need(
      (flags & 0xf7f1) == 0 && (compression == 0 || compression == 8),
      "Encrypted or unsupported ZIP flags/compression",
    )
    zip_need(
      zip_u16(data, cursor + 6) <= 20 && zip_u16(data, cursor + 34) == 0,
      "ZIP64 and split entries are unsupported",
    )
    zip_need(
      zip_u16(data, cursor + 30) == 0 && zip_u16(data, cursor + 32) == 0,
      "Extra fields and entry comments are unsupported",
    )
    let attrs = zip_u32(data, cursor + 38)
    let kind = (attrs >> 16) & 0xf000U
    zip_need(
      (attrs & 0x10U) == 0 && (kind == 0U || kind == 0x8000U),
      "Only regular files are supported; directories and links are refused",
    )
    let name_length = zip_u16(data, cursor + 28)
    zip_need(
      name_length > 0 && cursor + 46 + name_length <= end,
      "Truncated or empty filename",
    )
    let name = carrier_text({
      name: "ZIP filename",
      data: data[cursor + 46:cursor + 46 + name_length].to_owned(),
    })
    ignore(collection_path(name))
    zip_need(!names.contains(name), "Duplicate ZIP filenames are ambiguous")
    names.add(name)
    let compressed = zip_number(data, cursor + 20)
    let expanded = zip_number(data, cursor + 24)
    total += expanded.to_int64()
    carrier_sizes(expanded, total, limits)
    let crc = zip_u32(data, cursor + 16)
    let offset = zip_number(data, cursor + 42)
    zip_need(offset + 30 <= directory, "Truncated local header")
    zip_need(
      zip_u32(data, offset) == 0x04034b50U &&
      zip_u16(data, offset + 4) == zip_u16(data, cursor + 6) &&
      zip_u16(data, offset + 6) == flags &&
      zip_u16(data, offset + 8) == compression,
      "Local and central headers disagree",
    )
    zip_need(
      zip_u32(data, offset + 10) == zip_u32(data, cursor + 12),
      "Local and central timestamps disagree",
    )
    zip_need(
      zip_u16(data, offset + 26) == name_length &&
      zip_u16(data, offset + 28) == 0,
      "Local filename length/extra fields disagree",
    )
    let start = offset + 30 + name_length
    zip_need(
      start + compressed <= directory,
      "Member payload exceeds local region",
    )
    zip_need(
      data[offset + 30:start] == data[cursor + 46:cursor + 46 + name_length],
      "Local and central filenames disagree",
    )
    let mut entry_end = start + compressed
    if (flags & 8) == 0 {
      zip_need(
        zip_u32(data, offset + 14) == crc &&
        zip_number(data, offset + 18) == compressed &&
        zip_number(data, offset + 22) == expanded,
        "Local CRC or sizes disagree",
      )
    } else {
      for
        (at, expected) in [
          (14, crc),
          (18, compressed.reinterpret_as_uint()),
          (22, expanded.reinterpret_as_uint()),
        ] {
        let value = zip_u32(data, offset + at)
        zip_need(
          value == 0U || value == expected,
          "Inconsistent descriptor placeholders",
        )
      }
      zip_need(entry_end + 12 <= directory, "Missing classic data descriptor")
      if zip_u32(data, entry_end) == 0x08074b50U {
        entry_end += 4
      }
      zip_need(entry_end + 12 <= directory, "Truncated data descriptor")
      zip_need(
        zip_u32(data, entry_end) == crc &&
        zip_number(data, entry_end + 4) == compressed &&
        zip_number(data, entry_end + 8) == expanded,
        "Invalid data descriptor",
      )
      entry_end += 12
    }
    entries.push({
      name,
      offset,
      end: entry_end,
      start,
      compressed,
      expanded,
      crc,
      compression,
    })
    cursor += 46 + name_length
  }
  zip_need(cursor == end, "Undeclared central data")
  entries.sort_by((a, b) => a.offset.compare(b.offset))
  let mut next = 0
  for entry in entries {
    zip_need(
      entry.offset == next,
      "Overlapping, hidden, prefixed or gapped local records",
    )
    next = entry.end
  }
  zip_need(next == directory, "Undeclared local data")
  entries
}

///|
fn zip_expand(
  data : Bytes,
  entry : ZipMember,
) -> CarrierMember raise @ledger.InputError {
  let compressed = data[entry.start:entry.start + entry.compressed].to_owned()
  let decoded = if entry.compression == 0 {
    zip_need(entry.compressed == entry.expanded, "Stored entry sizes disagree")
    compressed
  } else {
    let output = @fzip.inflate_sync(compressed.to_fixedarray(), opts={
      out: Some(FixedArray::make(entry.expanded, b'\x00')),
      dictionary: None,
      max_input_size: compressed.length().max(1),
      max_output_size: entry.expanded.max(1),
    }) catch {
      @fzip.FzipError::FzipError(message~, ..) =>
        raise bad("ZipDeflate", entry.name, message)
    }
    Bytes::from_array(output[:])
  }
  zip_need(
    decoded.length() == entry.expanded,
    "Expanded size differs from declared size",
  )
  zip_need(
    @fzip.crc32(decoded.to_fixedarray()) == entry.crc,
    "ZIP entry CRC-32 mismatch",
  )
  { name: entry.name, data: decoded, }
}

///|
/// Deterministic classic ZIP carrier for the sealed full-plan file pack.
/// Compression is supplied by hustcer/fzip; this API is not a general archiver.
pub fn Evidence::zip_pack(
  self : Evidence,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
  max_bytes~ : Int32 = 16777216,
) -> Bytes raise @ledger.InputError {
  carrier_budget(0, max_bytes)
  let entries = carrier_pack(self, limits)
  let result = @fzip.zip_sync_checked(
    entries.map(entry => (entry.name, entry.data.to_fixedarray())),
  ) catch {
    @fzip.FzipError::FzipError(message~, ..) =>
      raise bad("ZipWrite", "$", message)
  }
  let bytes = Bytes::from_array(result[:])
  ignore(zip_entries(bytes, limits, max_bytes))
  bytes
}

///|
/// Reject unsupported carrier metadata, then verify original XML, full plan,
/// policy and whole evidence digest. This does not authenticate the sender.
pub fn decode_zip_pack(
  data : Bytes,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
  max_bytes~ : Int32 = 16777216,
) -> Evidence raise @ledger.InputError {
  let entries = zip_entries(data, limits, max_bytes)
  guard entries.iter().find_first(entry => entry.name == "index.json")
    is Some(index_entry) else {
    raise bad("MissingPackFile", "index.json", "ZIP pack requires its index")
  }
  let index_entry = zip_expand(data, index_entry)
  let index = decode_pack_index(carrier_text(index_entry), limits~)
  let required = Set::from_array(index.filenames())
  zip_need(
    entries.length() == required.length() + 1,
    "Pack entry inventory differs from index",
  )
  for entry in entries {
    zip_need(
      entry.name == "index.json" || required.contains(entry.name),
      "Undeclared pack entry",
    )
  }
  carrier_restore(entries.map(entry => zip_expand(data, entry)), limits)
}
