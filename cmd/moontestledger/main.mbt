///|
async fn main {
  let code = @cli.run(@env.args()[1:].to_owned())
  process_exit(code)
}

///|
#cfg(target="native")
extern "C" fn process_exit(code : Int32) = "exit"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn process_exit(code : Int32) = "moonbitlang/async" "runtime/exit"
