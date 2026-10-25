///|
// The option is trailing and reserved only for evidence-creation commands.
// Validate before input reads so invalid invocations have no output side effect.
fn output_arguments(
  arguments : Array[String],
) -> (Array[String], String?) raise @ledger.InputError {
  let positions = arguments.iter().filter(arg => arg == "--output").count()
  if positions == 0 {
    return (arguments, None)
  }
  if positions != 1 ||
    arguments.length() < 3 ||
    arguments[arguments.length() - 2] != "--output" {
    raise refusal(
      "Usage", "/arguments", "Use exactly one trailing --output NEW.json",
    )
  }
  if ![
      "archive", "collect", "collect-zip", "collect-tar", "merge", "retry", "append",
    ].contains(arguments[0]) {
    raise refusal(
      "Usage", "/arguments", "--output is supported by archive, collect, collect-zip, collect-tar, merge, retry and append",
    )
  }
  let path = arguments[arguments.length() - 1]
  if path.is_empty() {
    raise refusal(
      "OutputPath", "/arguments", "Output filename must not be empty",
    )
  }
  (arguments[:arguments.length() - 2].to_owned(), Some(path))
}

///|
async fn emit_evidence(text : String, output : String?) -> Unit {
  match output {
    None => @stdio.stdout.write(text + "\n")
    Some(path) =>
      write_carrier(path, @utf8.encode(text + "\n")) catch {
        error =>
          raise refusal(
            "OutputWrite",
            path,
            "Cannot create a new UTF-8 evidence file (existing paths are never overwritten): " +
            error.to_string(),
          )
      }
  }
}
