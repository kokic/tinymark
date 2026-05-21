///|
type HtmlNode = @sexp.SexpNode

///|
priv struct Binding {
  name : String
  value : Value
}

///|
pub fn altsia_to_sexp_nodes(source : String) -> Result[Array[HtmlNode], String] {
  parse_altsia(source).bind(fn(nodes) { compile_document(nodes) })
}

///|
pub fn altsia_to_html(source : String) -> Result[String, String] {
  altsia_to_sexp_nodes(source).map(@sexp.render_html)
}

///|
fn compile_document(nodes : Array[Node]) -> Result[Array[HtmlNode], String] {
  let env : Array[Binding] = []
  compile_node_sequence(nodes, env, 1, true)
}

///|
fn compile_node_sequence(
  nodes : Array[Node],
  env : Array[Binding],
  heading_level : Int,
  wrap_paragraphs : Bool,
) -> Result[Array[HtmlNode], String] {
  let out : Array[HtmlNode] = []
  let inline_run : Array[HtmlNode] = []
  let local_env = clone_env(env)
  for node in nodes {
    match node {
      Def(name, value) => bind_value(local_env, name, value)
      Meta(attrs) =>
        for attr in attrs {
          match attr {
            (name, Some(value)) => bind_value(local_env, name, value)
            (_, None) => ()
          }
        }
      _ =>
        match compile_node(node, local_env, heading_level) {
          Err(error) => return Err(error)
          Ok(compiled) =>
            for html_node in compiled {
              if wrap_paragraphs && is_inline_html_node(html_node) {
                append_with_paragraph_splits(inline_run, out, html_node)
              } else {
                flush_paragraph(inline_run, out)
                out.push(html_node)
              }
            }
        }
    }
  }
  flush_paragraph(inline_run, out)
  Ok(out)
}

///|
fn compile_node(
  node : Node,
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], String] {
  match node {
    Text(text) => Ok([HtmlNode::Text(text)])
    TextInterp(text) =>
      interpolate(text, env).map(fn(value) { [HtmlNode::Text(value)] })
    Ref(name) =>
      match lookup(env, name) {
        Some(value) => value_to_nodes(value, env, heading_level)
        None => Ok([HtmlNode::Element(name, [], [])])
      }
    Element(tag, attrs, children) =>
      compile_element(tag, attrs, children, env, heading_level)
    When(name, children) =>
      match bool_binding(env, name) {
        Ok(true) => compile_node_sequence(children, env, heading_level, false)
        Ok(false) => Ok([])
        Err(error) => Err(error)
      }
    Unless(name, children) =>
      match bool_binding(env, name) {
        Ok(true) => Ok([])
        Ok(false) => compile_node_sequence(children, env, heading_level, false)
        Err(error) => Err(error)
      }
    Def(_, _) | Meta(_) => Ok([])
  }
}

///|
fn compile_element(
  tag : String,
  attrs : Array[(String, Value?)],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], String] {
  match tag {
    "section" => compile_section(attrs, children, env, heading_level)
    "list" => compile_mapped_element("ul", attrs, children, env, heading_level)
    "enum" => compile_mapped_element("ol", attrs, children, env, heading_level)
    "item" => compile_mapped_element("li", attrs, children, env, heading_level)
    "note" | "warning" | "tip" =>
      compile_admonition(tag, attrs, children, env, heading_level)
    "code" => compile_code(attrs, children, env, heading_level)
    "slot" => compile_slot(attrs, children, env, heading_level)
    _ => compile_mapped_element(tag, attrs, children, env, heading_level)
  }
}

///|
fn compile_mapped_element(
  tag : String,
  attrs : Array[(String, Value?)],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], String] {
  compile_attrs(attrs, env).bind(fn(html_attrs) {
    compile_node_sequence(children, env, heading_level, false).map(fn(
      html_children,
    ) {
      [HtmlNode::Element(tag, html_attrs, html_children)]
    })
  })
}

///|
fn compile_section(
  attrs : Array[(String, Value?)],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], String] {
  let html_attrs : Array[(String, String?)] = []
  let section_children : Array[HtmlNode] = []
  let mut title : String? = None
  for attr in attrs {
    match attr {
      ("title", Some(value)) =>
        match value_to_scalar(value, env) {
          Ok(text) => title = Some(text)
          Err(error) => return Err(error)
        }
      (name, value) =>
        match compile_attr_value(value, env) {
          Ok(compiled) => html_attrs.push((name, compiled))
          Err(error) => return Err(error)
        }
    }
  }
  match title {
    Some(text) => {
      let level = clamp_heading_level(heading_level)
      section_children.push(
        HtmlNode::Element("h" + level.to_string(), [], [HtmlNode::Text(text)]),
      )
    }
    None => ()
  }
  let compiled = match
    compile_node_sequence(children, env, heading_level + 1, true) {
    Ok(nodes) => nodes
    Err(error) => return Err(error)
  }
  for child in compiled {
    section_children.push(child)
  }
  Ok([HtmlNode::Element("section", html_attrs, section_children)])
}

///|
fn compile_admonition(
  kind : String,
  attrs : Array[(String, Value?)],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], String] {
  let html_attrs = match compile_attrs(attrs, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  append_class(html_attrs, kind)
  let html_children = match
    compile_node_sequence(children, env, heading_level, true) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok([HtmlNode::Element("aside", html_attrs, html_children)])
}

///|
fn compile_code(
  attrs : Array[(String, Value?)],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], String] {
  let html_attrs = match compile_attrs(attrs, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut lang : String? = None
  for attr in html_attrs {
    match attr {
      ("lang", Some(value)) => lang = Some(value)
      _ => ()
    }
  }
  let source = match plain_text(children, env, heading_level) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let code_attrs : Array[(String, String?)] = []
  match lang {
    Some(value) => code_attrs.push(("class", Some("lang-" + value)))
    None => ()
  }
  Ok([
    HtmlNode::Element("pre", [], [
      HtmlNode::Element("code", code_attrs, [HtmlNode::Text(source)]),
    ]),
  ])
}

///|
fn compile_slot(
  attrs : Array[(String, Value?)],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], String] {
  let html_attrs = match compile_attrs(attrs, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let source = match plain_text(children, env, heading_level) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok([HtmlNode::Element("pre", html_attrs, [HtmlNode::Text(source)])])
}

///|
fn plain_text(
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[String, String] {
  let nodes = match compile_node_sequence(children, env, heading_level, false) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let parts : Array[String] = []
  for node in nodes {
    match node {
      HtmlNode::Text(text) => parts.push(text)
      _ => return Err("expected plain text content")
    }
  }
  Ok(parts.join(""))
}

///|
fn compile_attrs(
  attrs : Array[(String, Value?)],
  env : Array[Binding],
) -> Result[Array[(String, String?)], String] {
  let html_attrs : Array[(String, String?)] = []
  for attr in attrs {
    match attr {
      (name, value) =>
        match compile_attr_value(value, env) {
          Ok(compiled) => html_attrs.push((name, compiled))
          Err(error) => return Err(error)
        }
    }
  }
  Ok(html_attrs)
}

///|
fn compile_attr_value(
  value : Value?,
  env : Array[Binding],
) -> Result[String?, String] {
  match value {
    None => Ok(None)
    Some(v) => value_to_scalar(v, env).map(fn(text) { Some(text) })
  }
}

///|
fn value_to_scalar(
  value : Value,
  env : Array[Binding],
) -> Result[String, String] {
  match value {
    Scalar(text) => Ok(text)
    Bool(value) => Ok(if value { "true" } else { "false" })
    Interp(template) => interpolate(template, env)
    Fragment(_) => Err("expected scalar value")
  }
}

///|
fn value_to_nodes(
  value : Value,
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], String] {
  match value {
    Scalar(text) => Ok([HtmlNode::Text(text)])
    Bool(value) => Ok([HtmlNode::Text(if value { "true" } else { "false" })])
    Interp(template) =>
      interpolate(template, env).map(fn(text) { [HtmlNode::Text(text)] })
    Fragment(nodes) => compile_node_sequence(nodes, env, heading_level, false)
  }
}

///|
fn interpolate(
  template : String,
  env : Array[Binding],
) -> Result[String, String] {
  let chars = template.to_array()
  let parts : Array[String] = []
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '(' {
      let mut end = index + 1
      while end < chars.length() && chars[end] != ')' {
        end += 1
      }
      if end >= chars.length() {
        return Err("unterminated interpolation")
      }
      let name = String::from_array(chars.view(start=index + 1, end~))
      match lookup(env, name) {
        Some(value) =>
          match value_to_scalar(value, env) {
            Ok(text) => parts.push(text)
            Err(error) => return Err(error)
          }
        None => return Err("unbound interpolation name: " + name)
      }
      index = end + 1
    } else {
      let start = index
      while index < chars.length() && chars[index] != '(' {
        index += 1
      }
      parts.push(String::from_array(chars.view(start~, end=index)))
    }
  }
  Ok(parts.join(""))
}

///|
fn bool_binding(env : Array[Binding], name : String) -> Result[Bool, String] {
  match lookup(env, name) {
    Some(Bool(value)) => Ok(value)
    Some(Scalar("true")) => Ok(true)
    Some(Scalar("false")) => Ok(false)
    Some(_) => Err("condition is not a boolean binding: " + name)
    None => Err("unbound condition name: " + name)
  }
}

///|
fn lookup(env : Array[Binding], name : String) -> Value? {
  let mut index = env.length()
  while index > 0 {
    index -= 1
    let binding = env[index]
    if binding.name == name {
      return Some(binding.value)
    }
  }
  None
}

///|
fn bind_value(env : Array[Binding], name : String, value : Value) -> Unit {
  env.push({ name, value })
}

///|
fn clone_env(env : Array[Binding]) -> Array[Binding] {
  let cloned : Array[Binding] = []
  for binding in env {
    cloned.push(binding)
  }
  cloned
}

///|
fn flush_paragraph(inline_run : Array[HtmlNode], out : Array[HtmlNode]) -> Unit {
  if !inline_run.is_empty() {
    out.push(HtmlNode::Element("p", [], clone_html_nodes(inline_run)))
    inline_run.clear()
  }
}

///|
fn append_with_paragraph_splits(
  inline_run : Array[HtmlNode],
  out : Array[HtmlNode],
  node : HtmlNode,
) -> Unit {
  match node {
    HtmlNode::Text(text) if text.contains("\n\n") =>
      append_text_with_paragraph_splits(inline_run, out, text)
    _ => inline_run.push(node)
  }
}

///|
fn append_text_with_paragraph_splits(
  inline_run : Array[HtmlNode],
  out : Array[HtmlNode],
  text : String,
) -> Unit {
  let chars = text.to_array()
  let mut start = 0
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '\n' &&
      index + 1 < chars.length() &&
      chars[index + 1] == '\n' {
      if index > start {
        inline_run.push(
          HtmlNode::Text(String::from_array(chars.view(start~, end=index))),
        )
      }
      flush_paragraph(inline_run, out)
      index += 2
      start = index
    } else {
      index += 1
    }
  }
  if start < chars.length() {
    inline_run.push(HtmlNode::Text(String::from_array(chars.view(start~))))
  }
}

///|
fn clone_html_nodes(nodes : Array[HtmlNode]) -> Array[HtmlNode] {
  let cloned : Array[HtmlNode] = []
  for node in nodes {
    cloned.push(node)
  }
  cloned
}

///|
fn is_inline_html_node(node : HtmlNode) -> Bool {
  match node {
    HtmlNode::Text(_) => true
    HtmlNode::Comment(_) => false
    HtmlNode::Element(tag, _, _) => !is_block_tag(tag)
  }
}

///|
fn is_block_tag(tag : String) -> Bool {
  tag == "section" ||
  tag == "ul" ||
  tag == "ol" ||
  tag == "li" ||
  tag == "table" ||
  tag == "thead" ||
  tag == "tbody" ||
  tag == "tr" ||
  tag == "figure" ||
  tag == "aside" ||
  tag == "pre" ||
  tag == "p" ||
  tag == "blockquote" ||
  tag == "hr" ||
  tag.has_prefix("h")
}

///|
fn append_class(attrs : Array[(String, String?)], class_name : String) -> Unit {
  let mut found = false
  for i in 0..<attrs.length() {
    match attrs[i] {
      ("class", Some(value)) => {
        attrs[i] = ("class", Some(value + " " + class_name))
        found = true
      }
      ("class", None) => {
        attrs[i] = ("class", Some(class_name))
        found = true
      }
      _ => ()
    }
  }
  if !found {
    attrs.push(("class", Some(class_name)))
  }
}

///|
fn clamp_heading_level(level : Int) -> Int {
  if level < 1 {
    1
  } else if level > 6 {
    6
  } else {
    level
  }
}
