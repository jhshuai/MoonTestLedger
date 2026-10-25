///|
test "output option is trailing unique command-scoped and does not mutate arguments" {
  let args = ["collect", "spec.json", "reports", "--output", "new.json"]
  let (actual, output) = output_arguments(args)
  assert_eq(actual, ["collect", "spec.json", "reports"])
  assert_eq(output, Some("new.json"))
  assert_eq(args.length(), 5)
  for
    invalid in [
      ["verify", "input.json", "--output", "new.json"],
      ["archive", "--output"],
      ["collect", "--output", "spec", "reports"],
      ["collect", "spec", "reports", "--output", "a", "--output", "b"],
      ["collect", "spec", "reports", "--output", ""],
    ] {
    assert_true(
      (try output_arguments(invalid) catch {
        _ => None
      } noraise {
        _ => Some(())
      })
      is None,
    )
  }
  assert_eq(output_arguments(["verify", "input.json"]).1, None)
}

///|
async test "UTF8 output preserves Unicode no BOM and refuses overwrites without altering files" {
  let root = @fs.tmpdir(prefix="mtl-output")
  defer @fs.rmdir(root)
  let path = root + "/evidence.json"
  defer @fs.remove(path)
  let source = "{\"原始\":\"网络故障😀\"}"
  emit_evidence(source, Some(path))
  assert_eq(@fs.read_file(path).binary(), @utf8.encode(source + "\n"))
  assert_true(
    (try emit_evidence("replacement", Some(path)) catch {
      _ => None
    } noraise {
      _ => Some(())
    })
    is None,
  )
  assert_eq(@fs.read_file(path).text(), source + "\n")
}
