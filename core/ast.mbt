///|
pub(all) struct SourceSpan {
  line : Int
  column : Int
  marker_column : Int
  line_text : String
}

///|
fn SourceSpan::error(self : SourceSpan, message : String) -> String {
  "compile error at line " +
  self.line.to_string() +
  ", column " +
  self.column.to_string() +
  ": " +
  message +
  "\n" +
  self.line.to_string() +
  " | " +
  self.line_text +
  "\n" +
  repeat_string(" ", self.line.to_string().length()) +
  " | " +
  repeat_string(" ", self.marker_column - 1) +
  "^"
}

///|
pub(all) enum Value {
  Scalar(String, SourceSpan)
  Bool(Bool, SourceSpan)
  Fragment(Array[Node], SourceSpan)
  Interp(String, SourceSpan)
}

///|
pub(all) struct Attr {
  name : String
  value : Value?
  span : SourceSpan
}

///|
pub(all) enum Node {
  Text(String, SourceSpan)
  TextInterp(String, SourceSpan)
  Element(String, Array[Attr], Array[Node], SourceSpan)
  HtmlHead(Array[Attr], Array[Node], SourceSpan)
  Ref(String, SourceSpan)
  Let(String, Value, SourceSpan)
  Def(String, Array[String], Array[Node], SourceSpan)
  Meta(Array[Attr], SourceSpan)
  When(String, Array[Node], SourceSpan)
  Unless(String, Array[Node], SourceSpan)
}

///|
fn Value::span(self : Value) -> SourceSpan {
  match self {
    Scalar(_, span) | Bool(_, span) | Fragment(_, span) | Interp(_, span) =>
      span
  }
}

///|
fn Node::span(self : Node) -> SourceSpan {
  match self {
    Text(_, span)
    | TextInterp(_, span)
    | Element(_, _, _, span)
    | HtmlHead(_, _, span)
    | Ref(_, span)
    | Let(_, _, span)
    | Def(_, _, _, span)
    | Meta(_, span)
    | When(_, _, span)
    | Unless(_, _, span) => span
  }
}
