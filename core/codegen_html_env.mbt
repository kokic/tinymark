///|
fn lookup_value(env : Array[Binding], name : String) -> Value? {
  let mut index = env.length()
  while index > 0 {
    index -= 1
    let binding = env[index]
    if binding.name == name {
      match binding.value {
        BoundValue(value) => return Some(value)
        _ => ()
      }
    }
  }
  None
}

///|
fn bind_value(env : Array[Binding], name : String, value : Value) -> Unit {
  env.push({ name, value: BindingValue::BoundValue(value) })
}

///|
fn lookup_template(env : Array[Binding], name : String) -> Template? {
  let mut index = env.length()
  while index > 0 {
    index -= 1
    let binding = env[index]
    if binding.name == name {
      match binding.value {
        BoundTemplate(template) => return Some(template)
        _ => ()
      }
    }
  }
  None
}

///|
fn bind_template(
  env : Array[Binding],
  name : String,
  params : Array[String],
  body : Array[Node],
) -> Unit {
  env.push({
    name,
    value: BindingValue::BoundTemplate({ params, body, env: env.copy() }),
  })
}

///|
fn bind_meta_attr(env : Array[Binding], attr : Attr) -> Unit {
  match attr.value {
    Some(value) => bind_value(env, attr.name, value)
    None => ()
  }
}
