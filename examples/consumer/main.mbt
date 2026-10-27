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
  if input_arguments() is ["--review-inventory", before, proposed] {
    let baseline = @ledger.decode_plan(before)
    let candidate = @ledger.decode_plan(proposed)
    let review : @ledger.PlanReview = @ledger.review_plan(baseline, candidate)
    let changes : Array[@ledger.PlanChange] = review.changes()
    assert_true(
      changes.any(change => change.kind == @ledger.PlanChangeKind::CaseRemoved),
    )
    let restored = @ledger.decode_plan_review(review.encode())
    assert_eq(
      @ledger.encode_plan(restored.approve(baseline, approval=review.token())),
      @ledger.encode_plan(candidate),
    )
    println(review.encode())
    return
  }
  if input_arguments() is ["--reject-producer", xml, expected] {
    try @ledger.parse_junit(xml, report_id="rejected-producer") catch {
      @ledger.InputError::Invalid(diagnostic) => {
        assert_eq(diagnostic.code, expected)
        assert_true(diagnostic.path.contains("flakyFailure"))
        // A rejected report must not poison the next parse.
        assert_eq(
          @ledger.parse_junit("<testsuite><testcase name='ok'/></testsuite>").cases.length(),
          1,
        )
        println(@ledger.encode_diagnostic(diagnostic))
      }
    } noraise {
      _ => fail("unsupported embedded retry must not become a passing report")
    }
    return
  }
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
      "observations": Json::array(
        @ledger.parse_junit(xml, report_id=id).cases.map(case => {
          Json::array([
            Json::string(case.key.classname),
            Json::string(case.key.name),
            Json::string(
              match case.outcome {
                Pass => "pass"
                Failure => "failure"
                Error => "error"
                Skip => "skip"
              },
            ),
          ])
        }),
      ),
    }).stringify(),
  )
}
