///|
// Called only for grammar-validated JSON number lexemes. Normalize decimal
// position exactly, without converting to Double (which can round fractions).
fn exact_positive_integer(source : String) -> Int32? {
  if source.has_prefix("-") {
    return None
  }
  let chars = source.to_array()
  let mut digits = 0
  let mut fractional = 0
  let mut after_dot = false
  let mut first_nonzero = -1
  let mut last_nonzero = -1
  let mut exponent_start = chars.length()
  for i, char in chars {
    if char is ('e' | 'E') {
      exponent_start = i + 1
      break
    }
    if char == '.' {
      after_dot = true
    } else {
      if char != '0' {
        if first_nonzero < 0 {
          first_nonzero = digits
        }
        last_nonzero = digits
      }
      digits += 1
      if after_dot {
        fractional += 1
      }
    }
  }
  if first_nonzero < 0 {
    return None
  }
  let mut negative_exponent = false
  let mut exponent = 0
  // Saturation is safe: a larger exponent cannot cancel the bounded mantissa
  // into a nonzero 32-bit integer. It also avoids exponent arithmetic overflow.
  let ceiling = source.length() + 10
  for char in chars[exponent_start:] {
    match char {
      '-' => negative_exponent = true
      '+' => ()
      _ => {
        let digit = char.to_int() - '0'.to_int()
        exponent = if exponent > (ceiling - digit) / 10 {
          ceiling
        } else {
          exponent * 10 + digit
        }
      }
    }
  }
  let exponent = if negative_exponent { -exponent } else { exponent }
  let cutoff = digits + exponent - fractional
  if last_nonzero >= cutoff || cutoff - first_nonzero > 10 {
    return None
  }
  let mut ordinal = 0
  let mut result = 0
  for char in chars {
    if char is ('e' | 'E') {
      break
    }
    if char != '.' {
      if ordinal >= first_nonzero && ordinal < cutoff {
        let digit = char.to_int() - '0'.to_int()
        if result > (2147483647 - digit) / 10 {
          return None
        }
        result = result * 10 + digit
      }
      ordinal += 1
    }
  }
  for _ in digits..<cutoff {
    if result > 2147483647 / 10 {
      return None
    }
    result *= 10
  }
  Some(result)
}
