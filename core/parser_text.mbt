///|
fn parse_name(cursor : Cursor) -> (String, Cursor) {
  let start = cursor.index
  let mut index = cursor.index
  while index < cursor.length() {
    let ch = cursor.char_at(index)
    if ch.is_whitespace() || ch == '(' || ch == ')' || ch == '"' || ch == '`' {
      break
    }
    if ch == '\\' && index + 1 < cursor.length() {
      index += 2
    } else {
      index += 1
    }
  }
  (cursor.slice_to_string(start, index), cursor.at(index))
}

///|
fn parse_raw_string(cursor : Cursor) -> Result[(String, Cursor), Diagnostic] {
  let buffer : Array[Char] = []
  let mut index = cursor.index + 1
  while index < cursor.length() {
    let ch = cursor.char_at(index)
    if ch == '\\' &&
      index + 1 < cursor.length() &&
      cursor.char_at(index + 1) == '`' {
      buffer.push('`')
      index += 2
      continue
    }
    if ch == '`' {
      return Ok((String::from_array(buffer.view()), cursor.at(index + 1)))
    }
    buffer.push(ch)
    index += 1
  }
  Err(cursor.error("unterminated raw string"))
}

///|
fn parse_quoted_string(cursor : Cursor) -> Result[(String, Cursor), Diagnostic] {
  let buffer : Array[Char] = []
  let mut index = cursor.index + 1
  while index < cursor.length() {
    let ch = cursor.char_at(index)
    if ch == '\\' && index + 1 < cursor.length() {
      buffer.push(cursor.char_at(index + 1))
      index += 2
      continue
    }
    if ch == '"' {
      return Ok((String::from_array(buffer.view()), cursor.at(index + 1)))
    }
    buffer.push(ch)
    index += 1
  }
  Err(cursor.error("unterminated interpolated string"))
}

///|
fn parse_text(cursor : Cursor) -> (String, Cursor) {
  let buffer : Array[Char] = []
  let mut index = cursor.index
  while index < cursor.length() {
    let ch = cursor.char_at(index)
    if ch == '(' || ch == ')' || ch == '`' || ch == '"' || ch == '*' {
      break
    }
    if ch == ';' &&
      index + 1 < cursor.length() &&
      cursor.char_at(index + 1) == ';' {
      break
    }
    if ch == '\n' {
      let mut next = index + 1
      while next < cursor.length() {
        let space = cursor.char_at(next)
        if space == ' ' || space == '\t' || space == '\r' {
          next += 1
        } else {
          break
        }
      }
      if next < cursor.length() && cursor.char_at(next) == '\n' {
        buffer.push('\n')
        buffer.push('\n')
        index = next + 1
      } else {
        index += 1
      }
      continue
    }
    if ch == '\\' && index + 1 < cursor.length() {
      let escaped = cursor.char_at(index + 1)
      if escaped == '(' ||
        escaped == ')' ||
        escaped == '`' ||
        escaped == '*' ||
        escaped == '-' ||
        escaped == '+' {
        buffer.push(escaped)
        index += 2
        continue
      }
    }
    buffer.push(ch)
    index += 1
  }
  (smart_dashes(String::from_array(buffer.view())), cursor.at(index))
}

///|
fn parse_emphasis_or_text(
  cursor : Cursor,
) -> Result[(Node, Cursor), Diagnostic] {
  if cursor.starts_with("**") {
    capture_until(cursor.advance(2), "**").map(fn(result) {
      (
        Node::Element(
          "strong",
          [],
          [Node::Text(smart_dashes(result.0), cursor.advance(2).source_span())],
          cursor.source_span(),
        ),
        result.1,
      )
    })
  } else {
    capture_until(cursor.advance(1), "*").map(fn(result) {
      (
        Node::Element(
          "em",
          [],
          [Node::Text(smart_dashes(result.0), cursor.advance(1).source_span())],
          cursor.source_span(),
        ),
        result.1,
      )
    })
  }
}

///|
fn capture_until(
  cursor : Cursor,
  marker : String,
) -> Result[(String, Cursor), Diagnostic] {
  let buffer : Array[Char] = []
  let mut scan = cursor
  while !scan.is_end() {
    if scan.starts_with(marker) {
      return Ok(
        (String::from_array(buffer.view()), scan.advance(marker.length())),
      )
    }
    buffer.push(scan.char_at(scan.index))
    scan = scan.advance(1)
  }
  Err(cursor.error("unterminated inline marker"))
}

///|
fn smart_dashes(text : String) -> String {
  let chars = text.to_array()
  let out : Array[Char] = []
  let mut index = 0
  while index < chars.length() {
    if index + 2 < chars.length() &&
      chars[index] == '-' &&
      chars[index + 1] == '-' &&
      chars[index + 2] == '-' {
      out.push('—')
      index += 3
    } else if index + 1 < chars.length() &&
      chars[index] == '-' &&
      chars[index + 1] == '-' {
      out.push('–')
      index += 2
    } else {
      out.push(chars[index])
      index += 1
    }
  }
  String::from_array(out.view())
}
