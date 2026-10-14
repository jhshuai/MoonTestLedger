///|
priv struct CarrierMember {
  name : String
  data : Bytes
}

///|
fn carrier_budget(
  length : Int32,
  maximum : Int32,
) -> Unit raise @ledger.InputError {
  if maximum <= 0 || maximum > 268435456 || length > maximum {
    raise bad(
      "TransportLimit", "$", "Transport budget must be 1..268435456 bytes and contain the whole archive",
    )
  }
}

///|
fn carrier_text(entry : CarrierMember) -> String raise @ledger.InputError {
  @utf8.decode(entry.data) catch {
    _ =>
      raise bad(
        "InvalidUtf8",
        entry.name,
        "Archive entry must contain exact valid UTF-8",
      )
  }
}

///|
fn carrier_pack(
  evidence : Evidence,
  limits : @ledger.Limits,
) -> Array[CarrierMember] raise @ledger.InputError {
  let (index, files) = evidence.detach(limits~)
  [
    { name: "index.json", data: @utf8.encode(index.encode(limits~)), },
    ..files.map(file => { name: file.name, data: @utf8.encode(file.xml), }),
  ]
}

///|
fn carrier_restore(
  entries : Array[CarrierMember],
  limits : @ledger.Limits,
) -> Evidence raise @ledger.InputError {
  guard entries.iter().find_first(entry => entry.name == "index.json")
    is Some(index_entry) else {
    raise bad(
      "MissingPackFile", "index.json", "Transport requires a file-pack index",
    )
  }
  let index = decode_pack_index(carrier_text(index_entry), limits~)
  let files = entries
    .filter(entry => entry.name != "index.json")
    .map(entry => { name: entry.name, xml: carrier_text(entry), })
  index.restore(files[:], limits~)
}

///|
fn carrier_sizes(
  size : Int32,
  total : Int64,
  limits : @ledger.Limits,
) -> Unit raise @ledger.InputError {
  if size.to_int64() > 4L * limits.max_source_units.to_int64() ||
    total >
    4L *
    (
      limits.max_total_source_units.to_int64() +
      limits.max_source_units.to_int64()
    ) {
    raise bad(
      "SourceLimit", "$", "Expanded archive entries exceed the source byte budget",
    )
  }
}
