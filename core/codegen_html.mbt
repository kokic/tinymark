///|
type HtmlNode = @sexp.SexpNode

///|
priv enum ContentModel {
  InlineOnly
  BlockFlow
  MixedFlow
}

///|
pub fn altsia_to_sexp_nodes(
  source : String,
) -> Result[Array[HtmlNode], Diagnostic] {
  parse_altsia(source).bind(compile_document)
}

///|
pub fn altsia_to_html(source : String) -> Result[String, Diagnostic] {
  altsia_to_sexp_nodes(source).map(@sexp.render_html)
}

///|
pub fn altsia_to_html_document(
  source : String,
  options? : HtmlDocumentOptions,
) -> Result[String, Diagnostic] {
  let document_options = match options {
    Some(value) => value
    None => HtmlDocumentOptions::default()
  }
  parse_altsia(source).bind(nodes => {
    compile_html_document(nodes, document_options)
  })
}

///|
fn compile_document(nodes : Array[Node]) -> Result[Array[HtmlNode], Diagnostic] {
  let env : Array[Binding] = []
  compile_node_sequence(nodes, env, 1, true, true)
}

///|
fn compile_node_sequence(
  nodes : Array[Node],
  env : Array[Binding],
  heading_level : Int,
  wrap_paragraphs : Bool,
  allow_html_head : Bool,
) -> Result[Array[HtmlNode], Diagnostic] {
  let out : Array[HtmlNode] = []
  let inline_run : Array[HtmlNode] = []
  let local_env = clone_env(env)
  prebind_direct_templates(local_env, nodes)
  for node in nodes {
    match node {
      Let(name, value, _) => bind_value(local_env, name, value)
      Def(name, params, body, _) => bind_template(local_env, name, params, body)
      Meta(attrs, _) =>
        for attr in attrs {
          bind_meta_attr(local_env, attr)
        }
      HtmlHead(_, _, _) if allow_html_head => ()
      _ =>
        match compile_node(node, local_env, heading_level, false) {
          Err(error) => return Err(error)
          Ok(compiled) =>
            for html_node in compiled {
              append_compiled_node(inline_run, out, html_node, wrap_paragraphs)
            }
        }
    }
  }
  flush_paragraph(inline_run, out)
  Ok(out)
}

///|
fn compile_inline_children(
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
  compile_node_sequence(children, env, heading_level, false, false)
}

///|
fn compile_block_children(
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
  compile_node_sequence(children, env, heading_level, true, false)
}

///|
fn compile_mixed_children(
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
  compile_node_sequence(
    children,
    env,
    heading_level,
    children_need_paragraphs(children, env),
    false,
  )
}

///|
fn prebind_direct_templates(env : Array[Binding], nodes : Array[Node]) -> Unit {
  for node in nodes {
    match node {
      Def(name, params, body, _) => bind_template(env, name, params, body)
      _ => ()
    }
  }
}

///|
fn compile_node(
  node : Node,
  env : Array[Binding],
  heading_level : Int,
  allow_html_head : Bool,
) -> Result[Array[HtmlNode], Diagnostic] {
  match node {
    Text(text, _) => Ok([HtmlNode::Text(text)])
    TextInterp(text, span) =>
      interpolate(text, env, span).map(fn(value) { [HtmlNode::Text(value)] })
    Ref(name, span) =>
      match lookup_value(env, name) {
        Some(value) => value_to_nodes(value, env, heading_level)
        None =>
          match lookup_template(env, name) {
            Some(template) =>
              expand_template(template, [], [], env, heading_level, span)
            None => Ok([HtmlNode::Element(name, [], [])])
          }
      }
    Element(tag, attrs, children, span) =>
      match lookup_template(env, tag) {
        Some(template) =>
          expand_template(template, attrs, children, env, heading_level, span)
        None =>
          compile_element(
            source_tag_name(tag),
            attrs,
            children,
            env,
            heading_level,
          )
      }
    HtmlHead(_, _, span) =>
      if allow_html_head {
        Ok([])
      } else {
        Err(
          span.diagnostic(
            DiagnosticPhase::Placement,
            "html.head is only allowed at document top level",
          ),
        )
      }
    When(name, children, span) =>
      match bool_binding(env, name, span) {
        Ok(true) => compile_inline_children(children, env, heading_level)
        Ok(false) => Ok([])
        Err(error) => Err(error)
      }
    Unless(name, children, span) =>
      match bool_binding(env, name, span) {
        Ok(true) => Ok([])
        Ok(false) => compile_inline_children(children, env, heading_level)
        Err(error) => Err(error)
      }
    Let(_, _, _) | Def(_, _, _, _) | Meta(_, _) => Ok([])
  }
}

///|
fn compile_element(
  tag : String,
  attrs : Array[Attr],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
  match tag {
    "_" => compile_inline_children(children, env, heading_level)
    "section" => compile_section(attrs, children, env, heading_level)
    "list" => compile_mapped_element("ul", attrs, children, env, heading_level)
    "enum" => compile_mapped_element("ol", attrs, children, env, heading_level)
    "item" => compile_mapped_element("li", attrs, children, env, heading_level)
    "fig" =>
      compile_mapped_element("figure", attrs, children, env, heading_level)
    "block" =>
      compile_mapped_element("div", attrs, children, env, heading_level)
    "note" | "warning" | "tip" =>
      compile_admonition(tag, attrs, children, env, heading_level)
    "codeblock" => compile_code(attrs, children, env, heading_level)
    "slot" => compile_slot(attrs, children, env, heading_level)
    _ => compile_mapped_element(tag, attrs, children, env, heading_level)
  }
}

///|
fn source_tag_name(tag : String) -> String {
  match tag {
    "-" => "item"
    _ => tag
  }
}

///|
fn compile_mapped_element(
  tag : String,
  attrs : Array[Attr],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
  compile_attrs(attrs, env).bind(fn(html_attrs) {
    compile_children_for_tag(tag, children, env, heading_level).map(fn(
      html_children,
    ) {
      [HtmlNode::Element(tag, html_attrs, html_children)]
    })
  })
}

///|
fn compile_children_for_tag(
  tag : String,
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
  match content_model(tag) {
    InlineOnly => compile_inline_children(children, env, heading_level)
    BlockFlow => compile_block_children(children, env, heading_level)
    MixedFlow => compile_mixed_children(children, env, heading_level)
  }
}

///|
fn content_model(tag : String) -> ContentModel {
  match tag {
    "blockquote" => ContentModel::BlockFlow
    "li" | "div" => ContentModel::MixedFlow
    _ => ContentModel::InlineOnly
  }
}

///|
fn children_need_paragraphs(
  children : Array[Node],
  env : Array[Binding],
) -> Bool {
  let local_env = clone_env(env)
  prebind_direct_templates(local_env, children)
  for child in children {
    match child {
      Let(name, value, _) => bind_value(local_env, name, value)
      Def(name, params, body, _) => bind_template(local_env, name, params, body)
      Meta(attrs, _) =>
        for attr in attrs {
          bind_meta_attr(local_env, attr)
        }
      _ => if node_needs_paragraph_context(child, local_env) { return true }
    }
  }
  false
}

///|
fn node_needs_paragraph_context(node : Node, env : Array[Binding]) -> Bool {
  match node {
    Text(text, _) => has_paragraph_break(text)
    TextInterp(text, _) => has_paragraph_break(text)
    Element(tag, _, _, _) => is_source_block_tag(tag)
    Ref(name, _) =>
      match lookup_value(env, name) {
        Some(Scalar(text, _)) => has_paragraph_break(text)
        Some(Interp(text, _)) => has_paragraph_break(text)
        Some(Fragment(nodes, _)) => children_need_paragraphs(nodes, env)
        _ => false
      }
    When(name, children, span) =>
      match bool_binding(env, name, span) {
        Ok(true) => children_need_paragraphs(children, env)
        _ => false
      }
    Unless(name, children, span) =>
      match bool_binding(env, name, span) {
        Ok(false) => children_need_paragraphs(children, env)
        _ => false
      }
    Let(_, _, _) | Def(_, _, _, _) | Meta(_, _) | HtmlHead(_, _, _) => false
  }
}

///|
fn is_source_block_tag(tag : String) -> Bool {
  match source_tag_name(tag) {
    "section"
    | "list"
    | "enum"
    | "item"
    | "table"
    | "thead"
    | "tbody"
    | "tr"
    | "fig"
    | "note"
    | "warning"
    | "tip"
    | "codeblock"
    | "slot"
    | "p"
    | "blockquote"
    | "hr"
    | "block" => true
    _ => false
  }
}

///|
fn compile_section(
  attrs : Array[Attr],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
  let html_attrs : Array[(String, String?)] = []
  let section_children : Array[HtmlNode] = []
  let mut title : String? = None
  for attr in attrs {
    if attr.name == "title" {
      match attr.value {
        Some(value) =>
          match value_to_scalar(value, env) {
            Ok(text) => title = Some(text)
            Err(error) => return Err(error)
          }
        None => ()
      }
    } else {
      match compile_attr_value(attr.value, env) {
        Ok(compiled) => html_attrs.push((attr.name, compiled))
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
    compile_block_children(children, env, heading_level + 1) {
    Ok(nodes) => nodes
    Err(error) => return Err(error)
  }
  append_html_nodes(section_children, compiled)
  Ok([HtmlNode::Element("section", html_attrs, section_children)])
}

///|
fn compile_admonition(
  kind : String,
  attrs : Array[Attr],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
  let html_attrs = match compile_attrs(attrs, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  append_class(html_attrs, kind)
  let html_children = match
    compile_block_children(children, env, heading_level) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok([HtmlNode::Element("aside", html_attrs, html_children)])
}

///|
fn compile_code(
  attrs : Array[Attr],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
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
  attrs : Array[Attr],
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
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
fn expand_template(
  template : Template,
  attrs : Array[Attr],
  children : Array[Node],
  call_env : Array[Binding],
  heading_level : Int,
  call_span : SourceSpan,
) -> Result[Array[HtmlNode], Diagnostic] {
  let values : Array[Value?] = []
  for _ in template.params {
    values.push(None)
  }
  for attr in attrs {
    match attr.value {
      None =>
        return Err(
          attr.span.diagnostic(
            DiagnosticPhase::Template,
            "template argument requires a value: " + attr.name,
          ),
        )
      Some(value) =>
        match param_index(template.params, attr.name) {
          Some(index) =>
            match values[index] {
              Some(_) =>
                return Err(
                  attr.span.diagnostic(
                    DiagnosticPhase::Template,
                    "duplicate template argument: " + attr.name,
                  ),
                )
              None => values[index] = Some(value)
            }
          None =>
            return Err(
              attr.span.diagnostic(
                DiagnosticPhase::Template,
                "unknown template argument: " + attr.name,
              ),
            )
        }
    }
  }
  let positional_args = positional_values(children)
  let mut next_param = 0
  for arg in positional_args {
    let mut found_slot = false
    while next_param < values.length() && !found_slot {
      match values[next_param] {
        Some(_) => next_param += 1
        None => found_slot = true
      }
    }
    if next_param >= values.length() {
      return Err(
        arg
        .span()
        .diagnostic(DiagnosticPhase::Template, "too many template arguments"),
      )
    }
    values[next_param] = Some(arg)
    next_param += 1
  }
  let template_env = clone_env(call_env)
  append_bindings(template_env, template.env)
  for index in 0..<template.params.length() {
    match values[index] {
      Some(value) => bind_value(template_env, template.params[index], value)
      None =>
        return Err(
          call_span.diagnostic(
            DiagnosticPhase::Template,
            "missing template argument: " + template.params[index],
          ),
        )
    }
  }
  compile_inline_children(template.body, template_env, heading_level)
}

///|
fn positional_values(children : Array[Node]) -> Array[Value] {
  let values : Array[Value] = []
  for child in children {
    match child {
      Text(text, span) => append_text_arg(values, text, span)
      TextInterp(text, span) => values.push(Value::Interp(text, span))
      Element("_", _, nodes, span) => values.push(Value::Fragment(nodes, span))
      _ => values.push(nodes_to_value([child]))
    }
  }
  values
}

///|
fn append_text_arg(
  values : Array[Value],
  text : String,
  span : SourceSpan,
) -> Unit {
  let trimmed = text.trim().to_owned()
  if !trimmed.is_empty() {
    values.push(Value::Scalar(trimmed, span))
  }
}

///|
fn param_index(params : Array[String], name : String) -> Int? {
  for index in 0..<params.length() {
    if params[index] == name {
      return Some(index)
    }
  }
  None
}

///|
fn plain_text(
  children : Array[Node],
  env : Array[Binding],
  heading_level : Int,
) -> Result[String, Diagnostic] {
  let parts : Array[String] = []
  let local_env = clone_env(env)
  prebind_direct_templates(local_env, children)
  for child in children {
    match child {
      Let(name, value, _) => bind_value(local_env, name, value)
      Def(name, params, body, _) => bind_template(local_env, name, params, body)
      Meta(attrs, _) =>
        for attr in attrs {
          bind_meta_attr(local_env, attr)
        }
      _ => {
        let nodes = match compile_node(child, local_env, heading_level, false) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        for node in nodes {
          match node {
            HtmlNode::Text(text) => parts.push(text)
            _ =>
              return Err(
                child
                .span()
                .diagnostic(
                  DiagnosticPhase::ContentModel,
                  "expected plain text content",
                ),
              )
          }
        }
      }
    }
  }
  Ok(parts.join(""))
}

///|
fn compile_attrs(
  attrs : Array[Attr],
  env : Array[Binding],
) -> Result[Array[(String, String?)], Diagnostic] {
  let html_attrs : Array[(String, String?)] = []
  for attr in attrs {
    match compile_attr_value(attr.value, env) {
      Ok(compiled) => html_attrs.push((attr.name, compiled))
      Err(error) => return Err(error)
    }
  }
  Ok(html_attrs)
}

///|
fn compile_attr_value(
  value : Value?,
  env : Array[Binding],
) -> Result[String?, Diagnostic] {
  match value {
    None => Ok(None)
    Some(v) => value_to_scalar(v, env).map(fn(text) { Some(text) })
  }
}

///|
fn value_to_scalar(
  value : Value,
  env : Array[Binding],
) -> Result[String, Diagnostic] {
  match value {
    Scalar(text, _) => Ok(text)
    Bool(value, _) => Ok(if value { "true" } else { "false" })
    Interp(template, span) => interpolate(template, env, span)
    Fragment(_, span) =>
      Err(
        span.diagnostic(
          DiagnosticPhase::Type,
          "expected scalar value, but got rich content",
        ),
      )
  }
}

///|
fn value_to_nodes(
  value : Value,
  env : Array[Binding],
  heading_level : Int,
) -> Result[Array[HtmlNode], Diagnostic] {
  match value {
    Scalar(text, _) => Ok([HtmlNode::Text(text)])
    Bool(value, _) => Ok([HtmlNode::Text(if value { "true" } else { "false" })])
    Interp(template, span) =>
      interpolate(template, env, span).map(fn(text) { [HtmlNode::Text(text)] })
    Fragment(nodes, _) => compile_inline_children(nodes, env, heading_level)
  }
}

///|
fn interpolate(
  template : String,
  env : Array[Binding],
  span : SourceSpan,
) -> Result[String, Diagnostic] {
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
        return Err(
          span.diagnostic(DiagnosticPhase::Syntax, "unterminated interpolation"),
        )
      }
      let name = String::from_array(chars.view(start=index + 1, end~))
      match lookup_value(env, name) {
        Some(value) =>
          match value_to_scalar(value, env) {
            Ok(text) => parts.push(text)
            Err(error) => return Err(error)
          }
        None =>
          return Err(
            span.diagnostic(
              DiagnosticPhase::Binding,
              "unbound interpolation name: " + name,
            ),
          )
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
fn bool_binding(
  env : Array[Binding],
  name : String,
  span : SourceSpan,
) -> Result[Bool, Diagnostic] {
  match lookup_value(env, name) {
    Some(Bool(value, _)) => Ok(value)
    Some(Scalar("true", _)) => Ok(true)
    Some(Scalar("false", _)) => Ok(false)
    Some(_) =>
      Err(
        span.diagnostic(
          DiagnosticPhase::Type,
          "condition is not a boolean binding: " + name,
        ),
      )
    None =>
      Err(
        span.diagnostic(
          DiagnosticPhase::Binding,
          "unbound condition name: " + name,
        ),
      )
  }
}
