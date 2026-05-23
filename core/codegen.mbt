///|
priv struct Binding {
  name : String
  value : BindingValue
}

///|
priv enum BindingValue {
  BoundValue(Value)
  BoundTemplate(Template)
}

///|
priv struct Template {
  params : Array[String]
  body : Array[Node]
  env : Array[Binding]
}
