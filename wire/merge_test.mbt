///|
fn partial_archive(
  ids : Array[String],
  reverse~ : Bool = false,
  deny~ : Bool = false,
  run~ : String = "run",
  revision~ : String = "rev",
  changed~ : Bool = false,
  smaller~ : Bool = false,
) -> @wire.Evidence raise {
  let a : @ledger.CaseKey = { classname: "C", name: "a", }
  let b : @ledger.CaseKey = { classname: "C", name: "b", }
  let keys = if smaller { [a] } else if reverse { [b, a] } else { [a, b] }
  let plan = @ledger.RunPlan::new(run, revision, [
    { id: "one", environment: "linux", shard: "one", attempt: 1, cases: keys, },
    {
      id: "two",
      environment: "windows",
      shard: "two",
      attempt: 1,
      cases: keys,
    },
  ])
  let ledger = @ledger.Ledger::new(plan)
  for id in ids {
    let source = if changed {
      "<testsuite><testcase classname='C' name='a'><failure>different</failure></testcase><testcase classname='C' name='b'/></testsuite>"
    } else {
      "<testsuite><testcase classname='C' name='a'/><testcase classname='C' name='b'/></testsuite>"
    }
    ledger.ingest({
      binding: {
        id,
        run_id: run,
        revision,
        environment: if id == "one" {
          "linux"
        } else {
          "windows"
        },
        shard: id,
        attempt: 1,
      },
      report: @junit.parse(source),
    })
  }
  @wire.decode_evidence(@wire.encode_evidence(ledger, deny_recovered=deny))
}

///|
fn merge_error(
  inputs : Array[@wire.Evidence],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(@wire.merge_evidence(inputs[:], limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
test "merge completes complementary shards preserves sources and canonicalizes inventory" {
  let one = partial_archive(["one"], reverse=true)
  let two = partial_archive(["two"])
  let a = @wire.merge_evidence([one, two][:])
  let b = @wire.merge_evidence([two, one][:])
  assert_eq(a.exit_code(), 0)
  assert_eq(a.summary().cases.length(), 4)
  assert_eq(a.encode(), b.encode())
  assert_eq(a.source("one"), one.source("one"))
  assert_eq(a.source("two"), two.source("two"))
  assert_eq(@wire.decode_evidence(a.encode()).summary(), a.summary())
  assert_eq(one.exit_code(), 3)
  assert_eq(two.exit_code(), 3)
  let empty = partial_archive([])
  let left = @wire.merge_evidence([a, empty][:])
  let right = @wire.merge_evidence(
    [one, @wire.merge_evidence([two, empty][:])][:],
  )
  assert_eq(left.encode(), right.encode())
  assert_eq(@wire.merge_evidence([a, a][:]).encode(), a.encode())
}

///|
test "merge keeps missing evidence and refuses plan policy and report conflicts atomically" {
  let one = partial_archive(["one"])
  let before = one.encode()
  assert_eq(@wire.merge_evidence([one, one][:]).exit_code(), 3)
  assert_eq(merge_error([]), "EmptyMerge")
  for
    incompatible in [
      partial_archive([], run="other"),
      partial_archive([], revision="other"),
      partial_archive([], smaller=true),
    ] {
    assert_eq(merge_error([one, incompatible]), "MergePlanMismatch")
  }
  assert_eq(
    merge_error([one, partial_archive([], deny=true)]),
    "MergePolicyMismatch",
  )
  assert_eq(
    merge_error([one, partial_archive(["one"], changed=true)]),
    "ConflictingReport",
  )
  assert_eq(one.encode(), before)
  assert_eq(
    @wire.merge_evidence([one, partial_archive(["two"])][:]).exit_code(),
    0,
  )
}

///|
test "merge reapplies combined budgets without charging identical documents twice" {
  let one = partial_archive(["one"])
  let two = partial_archive(["two"])
  let size = one.source("one").unwrap().length()
  let limits = {
    ..@ledger.Limits::default(),
    max_total_source_units: size * 2,
  }
  assert_eq(@wire.merge_evidence([one, two][:], limits~).exit_code(), 0)
  assert_eq(
    merge_error([one, two], limits={
      ..limits,
      max_total_source_units: size * 2 - 1,
    }),
    "SourceLimit",
  )
  assert_eq(
    @wire.merge_evidence([one, one][:], limits={
      ..limits,
      max_total_source_units: size,
    }).exit_code(),
    3,
  )
  assert_eq(
    merge_error([one, two], limits={ ..limits, max_reports: 1, }),
    "MergeLimit",
  )
  assert_eq(
    merge_error([one, two], limits={ ..limits, max_cases: 3, }),
    "CaseLimit",
  )
}
