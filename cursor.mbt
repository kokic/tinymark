///|
priv struct Cursor {
  chars : Array[Char]
  index : Int
}

///|
fn Cursor::new(source : String) -> Cursor {
  { chars: source.to_array(), index: 0 }
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
  { chars: self.chars, index: self.index + amount }
}

///|
fn Cursor::at(self : Cursor, index : Int) -> Cursor {
  { chars: self.chars, index }
}

///|
fn Cursor::error(self : Cursor, message : String) -> String {
  "parse error at offset " + self.index.to_string() + ": " + message
}

///|
fn Cursor::slice_to_string(self : Cursor, start : Int, end : Int) -> String {
  String::from_array(self.chars.view(start~, end~))
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
