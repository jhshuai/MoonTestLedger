///|
#cfg(target="js")
fn input_arguments() -> Array[String] {
  @env.args()[2:].to_owned()
}

///|
#cfg(not(target="js"))
fn input_arguments() -> Array[String] {
  @env.args()[1:].to_owned()
}

///|
// An independent module: domain types and methods are imported only through
// the public facade. Fixture content is supplied by the evaluator as arguments.
fn main raise {
  guard input_arguments() is [specification, id, xml] else {
    fail("expected collection JSON, report ID and original XML")
  }
  let spec = @ledger.decode_collection(specification)
  let original = spec.encode()
  let inputs : Array[@ledger.CollectedXml] = [{ id, xml, }]
  let evidence = spec.collect(inputs[:])
  let encoded = evidence.encode()
  assert_eq(evidence.source(id), Some(xml))
  assert_eq(@ledger.decode_evidence(encoded).encode(), encoded)
  let (index, files) = evidence.detach()
  assert_eq(
    @ledger.decode_pack_index(index.encode()).restore(files[:]).encode(),
    encoded,
  )
  assert_eq(@ledger.decode_zip_pack(evidence.zip_pack()).encode(), encoded)
  assert_eq(@ledger.decode_tar_pack(evidence.tar_pack()).encode(), encoded)
  let missing = spec.collect([][:])
  assert_eq(missing.exit_code(), 3)
  assert_eq(missing.snapshot().plan, evidence.snapshot().plan)
  let unexpected : Array[@ledger.CollectedXml] = [{ id: "undeclared", xml, }]
  assert_true(
    (try spec.collect(unexpected[:]) catch {
      _ => None
    } noraise {
      _ => Some(())
    })
    is None,
  )
  assert_eq(spec.encode(), original)
  assert_eq(spec.collect(inputs[:]).encode(), encoded)
  println(
    Json::object({
      "summary": @json.parse(
        @ledger.encode_summary(
          evidence.summary(),
          deny_recovered=evidence.deny_recovered(),
        ),
      ),
      "integrity": @json.parse(evidence.integrity().encode()),
      "missing_gate": Json::number(missing.exit_code().to_double()),
    }).stringify(),
  )
}
