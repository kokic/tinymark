///|
priv struct Cursor {
  chars : Array[Char]
  index : Int
  line_offset : Int
  column_offset : Int
}

///|
fn Cursor::new(source : String) -> Cursor {
  Cursor::new_at(source, 0, 0)
}

///|
fn Cursor::new_at(
  source : String,
  line_offset : Int,
  column_offset : Int,
) -> Cursor {
  { chars: source.to_array(), index: 0, line_offset, column_offset }
}

///|
fn Cursor::is_end(self : Cursor) -> Bool {
  self.index >= self.chars.length()
}

///|
fn Cursor::length(self : Cursor) -> Int {
  self.chars.length()
}

///|
fn Cursor::char_at(self : Cursor, index : Int) -> Char {
  self.chars[index]
}

///|
fn Cursor::peek(self : Cursor) -> Char? {
  if self.is_end() {
    None
  } else {
    Some(self.char_at(self.index))
  }
}

///|
fn Cursor::advance(self : Cursor, amount : Int) -> Cursor {
  { ..self, index: self.index + amount }
}

///|
fn Cursor::at(self : Cursor, index : Int) -> Cursor {
  { ..self, index, }
}

///|
fn Cursor::error(self : Cursor, message : String) -> String {
  let (local_line, local_column) = self.local_line_column()
  let line = self.line_offset + local_line
  let column = if local_line == 1 {
    self.column_offset + local_column
  } else {
    local_column
  }
  let (line_start, line_end) = self.line_bounds()
  let source_line = self.slice_to_string(line_start, line_end)
  (
    $|parse error at line \{line.to_string()}, column \{column.to_string()}: \{message}
    $|\{line.to_string()} | \{source_line}
    $|\{repeat_string(" ", line.to_string().length())} | \{repeat_string(" ", local_column - 1)}^
  )
}

///|
fn Cursor::slice_to_string(self : Cursor, start : Int, end : Int) -> String {
  String::from_array(self.chars.view(start~, end~))
}

///|
fn Cursor::line_column(self : Cursor) -> (Int, Int) {
  let (line, column) = self.local_line_column()
  if line == 1 {
    (self.line_offset + line, self.column_offset + column)
  } else {
    (self.line_offset + line, column)
  }
}

///|
fn Cursor::local_line_column(self : Cursor) -> (Int, Int) {
  let mut line = 1
  let mut column = 1
  let mut index = 0
  let end = if self.index > self.length() { self.length() } else { self.index }
  while index < end {
    if self.char_at(index) == '\n' {
      line += 1
      column = 1
    } else {
      column += 1
    }
    index += 1
  }
  (line, column)
}

///|
fn Cursor::line_bounds(self : Cursor) -> (Int, Int) {
  let mut current = if self.index > self.length() {
    self.length()
  } else {
    self.index
  }
  if current > 0 &&
    current == self.length() &&
    self.char_at(current - 1) == '\n' {
    current -= 1
  }
  let mut start = current
  while start > 0 && self.char_at(start - 1) != '\n' {
    start -= 1
  }
  let mut end = current
  while end < self.length() && self.char_at(end) != '\n' {
    end += 1
  }
  (start, end)
}

///|
fn repeat_string(text : String, count : Int) -> String {
  let parts : Array[String] = []
  for _ in 0..<count {
    parts.push(text)
  }
  parts.join("")
}

///|
fn Cursor::starts_with(self : Cursor, text : String) -> Bool {
  let chars = text.to_array()
  if self.index + chars.length() > self.length() {
    return false
  }
  for i in 0..<chars.length() {
    if self.char_at(self.index + i) != chars[i] {
      return false
    }
  }
  true
}

///|
fn Cursor::at_line_start(self : Cursor) -> Bool {
  self.index == 0 || self.char_at(self.index - 1) == '\n'
}

///|
fn Cursor::skip_spaces(self : Cursor) -> Cursor {
  let mut index = self.index
  while index < self.length() {
    let ch = self.char_at(index)
    if ch == ' ' || ch == '\t' || ch == '\r' {
      index += 1
    } else {
      break
    }
  }
  self.at(index)
}

///|
fn Cursor::skip_layout(self : Cursor) -> Cursor {
  let mut cursor = self
  let mut keep_going = true
  while keep_going {
    keep_going = false
    cursor = cursor.skip_spaces()
    if cursor.starts_with(";;") {
      cursor = skip_line_comment(cursor)
      keep_going = true
    }
    if cursor.peek() == Some('\n') {
      cursor = cursor.advance(1)
      keep_going = true
    }
  }
  cursor
}
