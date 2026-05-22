///|
pub(all) enum Value {
  Scalar(String)
  Bool(Bool)
  Fragment(Array[Node])
  Interp(String)
}

///|
pub(all) enum Node {
  Text(String)
  TextInterp(String)
  Element(String, Array[(String, Value?)], Array[Node])
  HtmlHead(Array[(String, Value?)], Array[Node])
  Ref(String)
  Def(String, Value)
  Meta(Array[(String, Value?)])
  When(String, Array[Node])
  Unless(String, Array[Node])
}
