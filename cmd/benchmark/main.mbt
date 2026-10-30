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
fn input_count(args : Array[String]) -> Int32? {
  guard args is [text] else { return None }
  let count = @string.parse_int(text) catch { _ => return None }
  if count >= 1 && count <= 100000 {
    Some(count)
  } else {
    None
  }
}

///|
fn main raise {
  guard input_count(input_arguments()) is Some(count) else {
    println(
      Json::object({
        "error": Json::object({
          "code": Json::string("BenchmarkSize"),
          "message": Json::string("case count must be 1..100000"),
        }),
      }).stringify(),
    )
    process_exit(2)
    return
  }
  println(measure(count).stringify())
}

///|
#cfg(target="native")
extern "C" fn process_exit(code : Int32) = "exit"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn process_exit(code : Int32) = "moonbitlang/async" "runtime/exit"

///|
#cfg(target="wasm-gc")
#unsafe_skip_stub_check
fn process_exit(code : Int32) = "__moonbit_sys_unstable" "exit"

///|
#cfg(target="js")
extern "js" fn process_exit(code : Int32) =
  #| function(code) { process.exit(code); }
