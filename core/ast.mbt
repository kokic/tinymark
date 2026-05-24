///|
pub(all) struct SourceSpan {
  line : Int
  column : Int
  marker_column : Int
  line_text : String
}

///|
pub(all) enum DiagnosticPhase {
  Syntax
  Template
  Binding
  Type
  ContentModel
  Placement
}

///|
pub(all) struct Diagnostic {
  phase : DiagnosticPhase
  message : String
  span : SourceSpan
  hint : String?
}

///|
fn DiagnosticPhase::label(self : DiagnosticPhase) -> String {
  match self {
    Syntax => "syntax"
    Template => "template"
    Binding => "binding"
    Type => "type"
    ContentModel => "content model"
    Placement => "placement"
  }
}

///|
fn SourceSpan::diagnostic(
  self : SourceSpan,
  phase : DiagnosticPhase,
  message : String,
  hint? : String,
) -> Diagnostic {
  { phase, message, span: self, hint }
}

///|
pub fn Diagnostic::render(self : Diagnostic) -> String {
  let span = self.span
  let rendered = self.phase.label() +
    " error at line " +
    span.line.to_string() +
    ", column " +
    span.column.to_string() +
    ": " +
    self.message +
    "\n" +
    span.line.to_string() +
    " | " +
    span.line_text +
    "\n" +
    repeat_string(" ", span.line.to_string().length()) +
    " | " +
    repeat_string(" ", span.marker_column - 1) +
    "^"
  match self.hint {
    Some(hint) => rendered + "\nhint: " + hint
    None => rendered
  }
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
