///|
async fn source_error(
  root : String,
  relative : String,
  limits : @ledger.Limits,
) -> String {
  let cache : Map[String, Map[String, String]] = Map([])
  try {
    ignore(collection_source(root, relative, cache, Ref(0), limits))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
    other => fail(other.to_string())
  }
}

///|
async test "declared collection distinguishes absent paths from directories casing and invalid UTF-8 then recovers" {
  let root = @fs.tmpdir(prefix="moontestledger-collection-kinds")
  defer @fs.rmdir(root)
  let cache : Map[String, Map[String, String]] = Map([])
  let limits = @ledger.Limits::default()
  assert_eq(
    collection_source(root, "absent/report.xml", cache, Ref(0), limits),
    None,
  )
  let path = root + "/report.xml"
  @fs.mkdir(path)
  assert_eq(source_error(root, "report.xml", limits), "CollectionFileKind")
  @fs.rmdir(path)
  let wrong_case = root + "/Report.xml"
  @fs.write_file(wrong_case, "<testsuite/>")
  assert_eq(source_error(root, "report.xml", limits), "CollectionPathCase")
  @fs.remove(wrong_case)
  @fs.write_file(path, b"\xff")
  defer @fs.remove(path)
  assert_eq(source_error(root, "report.xml", limits), "InvalidUtf8")
  let xml = "<testsuite><testcase name='正常😀'/></testsuite>"
  @fs.write_file(path, xml)
  let fresh : Map[String, Map[String, String]] = Map([])
  assert_eq(
    collection_source(root, "report.xml", fresh, Ref(0), limits),
    Some(xml),
  )
}

///|
async test "declared collection bounds directory visits inclusively and caches shared prefixes once" {
  let root = @fs.tmpdir(prefix="moontestledger-collection-limit")
  defer @fs.rmdir(root)
  let directory = root + "/reports"
  @fs.mkdir(directory)
  defer @fs.rmdir(directory)
  let path = directory + "/test.xml"
  @fs.write_file(path, "<testsuite/>")
  defer @fs.remove(path)
  let limits = { ..@ledger.Limits::default(), max_events: 2, }
  let cache : Map[String, Map[String, String]] = Map([])
  let visits = Ref(0)
  assert_eq(
    collection_source(root, "reports/test.xml", cache, visits, limits),
    Some("<testsuite/>"),
  )
  assert_eq(visits.val, 2)
  assert_eq(
    collection_source(root, "reports/test.xml", cache, visits, limits),
    Some("<testsuite/>"),
  )
  assert_eq(visits.val, 2)
  assert_eq(
    source_error(root, "reports/test.xml", { ..limits, max_events: 1, }),
    "CollectionEntryLimit",
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "declared collection rejects regular broken and parent directory symlinks on Unix native" {
  let root = @fs.tmpdir(prefix="moontestledger-collection-links")
  defer @fs.rmdir(root)
  let actual = root + "/original.xml"
  @fs.write_file(actual, "<testsuite/>")
  defer @fs.remove(actual)
  let link = root + "/report.xml"
  @fs.symlink(link, target=actual)
  assert_eq(
    source_error(root, "report.xml", @ledger.Limits::default()),
    "CollectionFileKind",
  )
  @fs.remove(link)
  @fs.symlink(link, target=root + "/does-not-exist.xml")
  assert_eq(
    source_error(root, "report.xml", @ledger.Limits::default()),
    "CollectionFileKind",
  )
  @fs.remove(link)
  let parent = root + "/reports"
  @fs.symlink(parent, target=root)
  defer @fs.remove(parent)
  assert_eq(
    source_error(root, "reports/original.xml", @ledger.Limits::default()),
    "CollectionFileKind",
  )
}
