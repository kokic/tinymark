///|
fn skip_line_comment(cursor : Cursor) -> Cursor {
  let mut index = cursor.index
  while index < cursor.length() && cursor.char_at(index) != '\n' {
    index += 1
  }
  cursor.at(index)
}

///|
fn skip_attach_space(cursor : Cursor) -> (Cursor, Bool) {
  let mut index = cursor.index
  let mut newline_count = 0
  while index < cursor.length() {
    let ch = cursor.char_at(index)
    if ch == ' ' || ch == '\t' || ch == '\r' {
      index += 1
      continue
    }
    if ch == '\n' {
      newline_count += 1
      if newline_count >= 2 {
        return (cursor.at(index), true)
      }
      index += 1
      continue
    }
    break
  }
  (cursor.at(index), false)
}

///|
pub fn parse_altsia(source : String) -> Result[Array[Node], String] {
  parse_nodes(Cursor::new(source), None).map(fn(result) { result.0 })
}

///|
fn parse_nodes(
  start : Cursor,
  close : Char?,
) -> Result[(Array[Node], Cursor), String] {
  let nodes : Array[Node] = []
  let mut cursor = start.skip_layout()
  while !cursor.is_end() {
    match close {
      Some(ch) if cursor.peek() == Some(ch) =>
        return Ok((nodes, cursor.advance(1)))
      _ => ()
    }
    if cursor.peek() == Some(')') {
      return Err(cursor.error("unexpected ')'"))
    }
    let parsed = parse_node(cursor)
    match parsed {
      Err(error) => return Err(error)
      Ok((node, next)) => {
        let (attached, after_attach) = maybe_attach_block_quote(node, next)
        nodes.push(attached)
        cursor = after_attach.skip_layout()
      }
    }
  }
  match close {
    Some(_) => Err(start.error("unterminated list"))
    None => Ok((nodes, cursor))
  }
}

///|
fn parse_node(cursor : Cursor) -> Result[(Node, Cursor), String] {
  let start = cursor.skip_spaces()
  if start.starts_with(";;") {
    return parse_node(skip_line_comment(start).skip_layout())
  }
  if start.at_line_start() &&
    (start.peek() == Some('-') || start.peek() == Some('+')) {
    return parse_list_sugar(start)
  }
  match start.peek() {
    None => Err(start.error("unexpected end of input"))
    Some('(') => parse_list(start)
    Some('`') =>
      parse_raw_string(start).map(fn(result) {
        (Node::Text(result.0), result.1)
      })
    Some('"') =>
      parse_quoted_string(start).map(fn(result) {
        (Node::TextInterp(result.0), result.1)
      })
    Some('*') => parse_emphasis_or_text(start)
    _ => {
      let (text, next) = parse_text(start)
      Ok((Node::Text(text), next))
    }
  }
}

///|
fn parse_list(open : Cursor) -> Result[(Node, Cursor), String] {
  let head_start = open.advance(1).skip_layout()
  let (head, after_head) = parse_name(head_start)
  if head.is_empty() {
    return Err(head_start.error("list head cannot be empty"))
  }
  match head {
    "def" => parse_def(after_head)
    "meta" => parse_meta(after_head)
    "when" => parse_conditional(after_head, true)
    "unless" => parse_conditional(after_head, false)
    _ => parse_element_or_ref(head, after_head)
  }
}

///|
fn parse_def(after_head : Cursor) -> Result[(Node, Cursor), String] {
  let name_start = after_head.skip_layout()
  let (name, after_name) = parse_name(name_start)
  if name.is_empty() {
    return Err(name_start.error("def name cannot be empty"))
  }
  let values : Array[Node] = []
  let mut cursor = after_name.skip_layout()
  while !cursor.is_end() && cursor.peek() != Some(')') {
    match parse_node(cursor) {
      Err(error) => return Err(error)
      Ok((node, next)) => {
        values.push(node)
        cursor = next.skip_layout()
      }
    }
  }
  if cursor.peek() != Some(')') {
    return Err(after_head.error("unterminated def"))
  }
  let value = nodes_to_value(values)
  Ok((Node::Def(name, value), cursor.advance(1)))
}

///|
fn nodes_to_value(nodes : Array[Node]) -> Value {
  if nodes.length() == 1 {
    match nodes[0] {
      Text(text) => scalar_or_bool(text)
      TextInterp(text) => Value::Interp(text)
      _ => Value::Fragment(nodes)
    }
  } else {
    Value::Fragment(nodes)
  }
}

///|
fn scalar_or_bool(text : String) -> Value {
  if text == "true" {
    Bool(true)
  } else if text == "false" {
    Bool(false)
  } else {
    Scalar(text)
  }
}

///|
fn parse_meta(after_head : Cursor) -> Result[(Node, Cursor), String] {
  let cursor = after_head.skip_layout()
  match cursor.peek() {
    Some('(') =>
      parse_attr_list(cursor).bind(fn(result) {
        let (attrs, next) = result
        let end = next.skip_layout()
        if end.peek() == Some(')') {
          Ok((Node::Meta(attrs), end.advance(1)))
        } else {
          Err(end.error("meta only accepts an attribute list"))
        }
      })
    _ => Err(cursor.error("meta requires an attribute list"))
  }
}

///|
fn parse_conditional(
  after_head : Cursor,
  is_when : Bool,
) -> Result[(Node, Cursor), String] {
  let condition_start = after_head.skip_layout()
  match parse_condition_ref(condition_start) {
    Err(error) => Err(error)
    Ok((name, after_condition)) =>
      match parse_nodes(after_condition, Some(')')) {
        Err(error) => Err(error)
        Ok((children, next)) =>
          if is_when {
            Ok((Node::When(name, children), next))
          } else {
            Ok((Node::Unless(name, children), next))
          }
      }
  }
}

///|
fn parse_condition_ref(cursor : Cursor) -> Result[(String, Cursor), String] {
  if cursor.peek() != Some('(') {
    return Err(cursor.error("condition must be a zero-argument name reference"))
  }
  let (name, after_name) = parse_name(cursor.advance(1).skip_layout())
  let end = after_name.skip_layout()
  if name.is_empty() || end.peek() != Some(')') {
    Err(cursor.error("condition must be a zero-argument name reference"))
  } else {
    Ok((name, end.advance(1)))
  }
}

///|
fn parse_element_or_ref(
  tag : String,
  after_head : Cursor,
) -> Result[(Node, Cursor), String] {
  let mut cursor = after_head.skip_layout()
  let attrs : Array[(String, Value?)] = []
  if cursor.peek() == Some('(') {
    match peek_attr_list(cursor) {
      true =>
        match parse_attr_list(cursor) {
          Ok((parsed_attrs, next)) => {
            for attr in parsed_attrs {
              attrs.push(attr)
            }
            cursor = next.skip_layout()
          }
          Err(error) => return Err(error)
        }
      false => ()
    }
  }
  match parse_nodes(cursor, Some(')')) {
    Err(error) => Err(error)
    Ok((children, next)) =>
      if attrs.is_empty() && children.is_empty() {
        Ok((Node::Ref(tag), next))
      } else {
        Ok((Node::Element(tag, attrs, children), next))
      }
  }
}

///|
fn peek_attr_list(cursor : Cursor) -> Bool {
  cursor.advance(1).skip_layout().peek() == Some(':')
}

///|
fn parse_attr_list(
  open : Cursor,
) -> Result[(Array[(String, Value?)], Cursor), String] {
  let attrs : Array[(String, Value?)] = []
  let mut cursor = open.advance(1).skip_layout()
  while !cursor.is_end() {
    cursor = cursor.skip_layout()
    match cursor.peek() {
      Some(')') => return Ok((attrs, cursor.advance(1)))
      Some(':') => {
        let (name, after_name) = parse_name(cursor.advance(1))
        if name.is_empty() {
          return Err(cursor.error("attribute name cannot be empty"))
        }
        let value_start = after_name.skip_layout()
        match value_start.peek() {
          Some(')') => {
            attrs.push((name, None))
            cursor = value_start
          }
          Some(':') => {
            attrs.push((name, None))
            cursor = value_start
          }
          _ =>
            match parse_value(value_start) {
              Ok((value, next)) => {
                attrs.push((name, Some(value)))
                cursor = next
              }
              Err(error) => return Err(error)
            }
        }
      }
      _ => return Err(cursor.error("expected attribute key"))
    }
  }
  Err(open.error("unterminated attribute list"))
}

///|
fn parse_value(cursor : Cursor) -> Result[(Value, Cursor), String] {
  match cursor.peek() {
    Some('`') =>
      parse_raw_string(cursor).map(fn(result) {
        (Value::Scalar(result.0), result.1)
      })
    Some('"') =>
      parse_quoted_string(cursor).map(fn(result) {
        (Value::Interp(result.0), result.1)
      })
    Some('(') => parse_value_ref(cursor)
    _ => {
      let (name, next) = parse_name(cursor)
      if name.is_empty() {
        Err(cursor.error("expected value"))
      } else {
        Ok((scalar_or_bool(name), next))
      }
    }
  }
}

///|
fn parse_value_ref(cursor : Cursor) -> Result[(Value, Cursor), String] {
  let (name, after_name) = parse_name(cursor.advance(1).skip_layout())
  let end = after_name.skip_layout()
  if name.is_empty() || end.peek() != Some(')') {
    Err(
      cursor.error("attribute value only accepts zero-argument name references"),
    )
  } else {
    Ok((Value::Interp("(" + name + ")"), end.advance(1)))
  }
}

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
fn parse_raw_string(cursor : Cursor) -> Result[(String, Cursor), String] {
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
fn parse_quoted_string(cursor : Cursor) -> Result[(String, Cursor), String] {
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
      if index + 1 < cursor.length() && cursor.char_at(index + 1) == '\n' {
        buffer.push('\n')
        buffer.push('\n')
        index += 2
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
  (String::from_array(buffer.view()), cursor.at(index))
}

///|
fn parse_emphasis_or_text(cursor : Cursor) -> Result[(Node, Cursor), String] {
  if cursor.starts_with("**") {
    capture_until(cursor.advance(2), "**").map(fn(result) {
      (Node::Element("strong", [], [Node::Text(result.0)]), result.1)
    })
  } else {
    capture_until(cursor.advance(1), "*").map(fn(result) {
      (Node::Element("em", [], [Node::Text(result.0)]), result.1)
    })
  }
}

///|
fn capture_until(
  cursor : Cursor,
  marker : String,
) -> Result[(String, Cursor), String] {
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
fn parse_list_sugar(cursor : Cursor) -> Result[(Node, Cursor), String] {
  let marker = match cursor.peek() {
    Some(ch) => ch
    None => return Err(cursor.error("expected list marker"))
  }
  let tag = if marker == '-' { "list" } else { "enum" }
  let items : Array[Node] = []
  let mut scan = cursor
  while !scan.is_end() && scan.at_line_start() && scan.peek() == Some(marker) {
    let content_start = scan.advance(1)
    let mut line_end = content_start.index
    while line_end < scan.length() && scan.char_at(line_end) != '\n' {
      line_end += 1
    }
    let line = scan
      .slice_to_string(content_start.index, line_end)
      .trim()
      .to_owned()
    let parsed_line = parse_altsia(line)
    match parsed_line {
      Ok(children) => items.push(Node::Element("item", [], children))
      Err(error) => return Err(error)
    }
    scan = scan.at(line_end)
    if scan.peek() == Some('\n') {
      scan = scan.advance(1)
    }
  }
  Ok((Node::Element(tag, [], items), scan))
}

///|
fn maybe_attach_block_quote(node : Node, cursor : Cursor) -> (Node, Cursor) {
  let (candidate, blocked) = skip_attach_space(cursor)
  if blocked || !candidate.starts_with("```") {
    return (node, cursor)
  }
  match parse_block_quote(candidate) {
    Ok((content, next)) =>
      match node {
        Element(tag, attrs, children) => {
          children.push(Node::Text(content))
          (Node::Element(tag, attrs, children), next)
        }
        Ref(name) => (Node::Element(name, [], [Node::Text(content)]), next)
        _ => (node, cursor)
      }
    Err(_) => (node, cursor)
  }
}

///|
fn parse_block_quote(cursor : Cursor) -> Result[(String, Cursor), String] {
  let mut fence_end = cursor.index
  while fence_end < cursor.length() && cursor.char_at(fence_end) != '\n' {
    fence_end += 1
  }
  let fence = cursor.slice_to_string(cursor.index, fence_end)
  if !fence.has_prefix("```") {
    return Err(cursor.error("expected block quote fence"))
  }
  let content_start = if fence_end < cursor.length() {
    fence_end + 1
  } else {
    fence_end
  }
  let mut index = content_start
  while index < cursor.length() {
    if index == 0 || cursor.char_at(index - 1) == '\n' {
      let line_end = find_line_end(cursor, index)
      let line = cursor.slice_to_string(index, line_end)
      if line == fence {
        return Ok(
          (cursor.slice_to_string(content_start, index), cursor.at(line_end)),
        )
      }
    }
    index += 1
  }
  Err(cursor.error("unterminated block quote"))
}

///|
fn find_line_end(cursor : Cursor, start : Int) -> Int {
  let mut index = start
  while index < cursor.length() &&
        cursor.char_at(index) != '\n' &&
        cursor.char_at(index) != ')' {
    index += 1
  }
  index
}
