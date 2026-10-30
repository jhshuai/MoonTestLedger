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
fn main raise {
  guard input_arguments() is [count] else {
    fail("usage: moon run --target TARGET cmd/benchmark -- CASES (1..100000)")
  }
  println(measure(@string.parse_int(count)).stringify())
}
