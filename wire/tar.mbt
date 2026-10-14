///|
fn tar_need(ok : Bool, message : String) -> Unit raise @ledger.InputError {
  if !ok {
    raise bad("TarProfile", "$", message)
  }
}

///|
fn tar_zero(data : BytesView) -> Bool {
  data.iter().all(byte => byte == b'\x00')
}

///|
fn tar_string(
  data : Bytes,
  start : Int32,
  width : Int32,
) -> String raise @ledger.InputError {
  let mut end = start + width
  for at in start..<end {
    if data[at] == b'\x00' {
      end = at
      break
    }
  }
  tar_need(
    tar_zero(data[end:start + width]),
    "Nonzero bytes after a terminated header string",
  )
  carrier_text({
    name: "USTAR header string",
    data: data[start:end].to_owned(),
  })
}

///|
fn tar_number(
  data : Bytes,
  start : Int32,
  width : Int32,
) -> Int64 raise @ledger.InputError {
  let mut value = 0L
  let mut digits = false
  let mut ended = false
  for at in start..<(start + width) {
    let byte = data[at].to_int()
    if byte == 0 || byte == 32 {
      if digits || byte == 0 {
        ended = true
      }
    } else {
      tar_need(
        !ended && byte >= 48 && byte <= 55,
        "Only nonnegative octal USTAR numbers are supported",
      )
      tar_need(
        value <= (9223372036854775807L - (byte - 48).to_int64()) / 8L,
        "USTAR numeric overflow",
      )
      value = value * 8L + (byte - 48).to_int64()
      digits = true
    }
  }
  value
}

///|
fn tar_entries(
  data : Bytes,
  limits : @ledger.Limits,
  maximum : Int32,
) -> Array[CarrierMember] raise @ledger.InputError {
  carrier_budget(data.length(), maximum)
  tar_need(
    data.length() >= 1024 && data.length() % 512 == 0,
    "USTAR requires whole blocks and two zero end blocks",
  )
  let result : Array[CarrierMember] = []
  let names : Set[String] = Set([])
  let mut total = 0L
  let mut cursor = 0
  for ;; {
    tar_need(cursor + 1024 <= data.length(), "Missing USTAR end blocks")
    if tar_zero(data[cursor:cursor + 512]) {
      tar_need(tar_zero(data[cursor:]), "Nonzero data after USTAR end marker")
      break
    }
    tar_need(result.length() < limits.max_reports + 1, "Too many USTAR members")
    tar_need(
      data[cursor + 257:cursor + 265] == b"ustar\x0000",
      "Only POSIX USTAR magic/version are supported",
    )
    let mut checksum = 0L
    for at in 0..<512 {
      checksum += if at >= 148 && at < 156 {
        32L
      } else {
        data[cursor + at].to_int().to_int64()
      }
    }
    tar_need(
      checksum == tar_number(data, cursor + 148, 8),
      "USTAR header checksum mismatch",
    )
    tar_need(
      data[cursor + 156] == b'0' || data[cursor + 156] == b'\x00',
      "Only regular files; directories, links, PAX, GNU and sparse extensions are refused",
    )
    tar_need(
      tar_zero(data[cursor + 157:cursor + 257]) &&
      tar_zero(data[cursor + 500:cursor + 512]),
      "Link targets or unknown USTAR header extension bytes",
    )
    ignore(tar_number(data, cursor + 100, 8))
    ignore(tar_number(data, cursor + 108, 8))
    ignore(tar_number(data, cursor + 116, 8))
    ignore(tar_number(data, cursor + 136, 12))
    ignore(tar_string(data, cursor + 265, 32))
    ignore(tar_string(data, cursor + 297, 32))
    tar_need(
      tar_number(data, cursor + 329, 8) == 0L &&
      tar_number(data, cursor + 337, 8) == 0L,
      "Device metadata on regular files is unsupported",
    )
    let prefix = tar_string(data, cursor + 345, 155)
    let base = tar_string(data, cursor, 100)
    tar_need(base != "", "Empty USTAR filename")
    let name = if prefix == "" { base } else { prefix + "/" + base }
    ignore(collection_path(name))
    tar_need(!names.contains(name), "Duplicate USTAR filename")
    names.add(name)
    let size = tar_number(data, cursor + 124, 12)
    tar_need(size <= 268435456L, "USTAR member exceeds the transport ceiling")
    total += size
    carrier_sizes(size.to_int(), total, limits)
    let start = cursor + 512
    let end = start + size.to_int()
    let next = start + (size.to_int() + 511) / 512 * 512
    tar_need(next <= data.length(), "Truncated USTAR payload")
    tar_need(tar_zero(data[end:next]), "Nonzero member block padding")
    result.push({ name, data: data[start:end].to_owned(), })
    cursor = next
  }
  result
}

///|
fn tar_write_string(header : Array[Byte], at : Int32, text : String) -> Unit {
  let bytes = @utf8.encode(text)
  for i in 0..<bytes.length() {
    header[at + i] = bytes[i]
  }
}

///|
fn tar_write_octal(
  header : Array[Byte],
  at : Int32,
  width : Int32,
  value : Int32,
) -> Unit {
  let mut remaining = value
  header[at + width - 1] = b'\x00'
  for i = width - 2; i >= 0; i = i - 1 {
    header[at + i] = (48 + remaining % 8).to_byte()
    remaining /= 8
  }
}

///|
fn tar_write(
  entries : Array[CarrierMember],
  maximum : Int32,
) -> Bytes raise @ledger.InputError {
  carrier_budget(0, maximum)
  let mut size = 1024L
  for entry in entries {
    tar_need(
      entry.name.length() <= 100,
      "Writer supports names up to 100 ASCII bytes",
    )
    ignore(collection_path(entry.name))
    size += 512L + (entry.data.length().to_int64() + 511L) / 512L * 512L
  }
  tar_need(
    size <= maximum.to_int64(),
    "USTAR output exceeds the configured transport budget",
  )
  let output : Array[Byte] = []
  for entry in entries {
    let header = Array::make(512, b'\x00')
    tar_write_string(header, 0, entry.name)
    for
      (at, width, value) in [
        (100, 8, 420),
        (108, 8, 0),
        (116, 8, 0),
        (124, 12, entry.data.length()),
        (136, 12, 0),
        (329, 8, 0),
        (337, 8, 0),
      ] {
      tar_write_octal(header, at, width, value)
    }
    header[156] = b'0'
    tar_write_string(header, 257, "ustar\u000000")
    for at in 148..<156 {
      header[at] = b' '
    }
    let checksum = header.fold(init=0, (sum, byte) => sum + byte.to_int())
    tar_write_octal(header, 148, 7, checksum)
    header[155] = b' '
    output.append(header)
    output.append(entry.data.to_array())
    let padding = (512 - entry.data.length() % 512) % 512
    for _ in 0..<padding {
      output.push(b'\x00')
    }
  }
  output.append(Array::make(1024, b'\x00'))
  Bytes::from_array(output[:])
}

///|
/// Deterministic uncompressed USTAR carrier with fixed regular-file metadata.
pub fn Evidence::tar_pack(
  self : Evidence,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
  max_bytes~ : Int32 = 16777216,
) -> Bytes raise @ledger.InputError {
  let bytes = tar_write(carrier_pack(self, limits), max_bytes)
  ignore(tar_entries(bytes, limits, max_bytes))
  bytes
}

///|
/// Restore only a sealed evidence pack; reject unsupported USTAR extensions,
/// duplicate/extra members, changed original XML or inconsistent full plan.
pub fn decode_tar_pack(
  data : Bytes,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
  max_bytes~ : Int32 = 16777216,
) -> Evidence raise @ledger.InputError {
  carrier_restore(tar_entries(data, limits, max_bytes), limits)
}
