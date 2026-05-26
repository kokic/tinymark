///|
pub(all) struct HtmlDocumentOptions {
  doctype : String?
  charset : String?
  viewport : String?
  enable_katex : Bool
}

///|
pub fn HtmlDocumentOptions::default() -> HtmlDocumentOptions {
  {
    doctype: Some("html"),
    charset: Some("utf-8"),
    viewport: Some("width=device-width, initial-scale=1"),
    enable_katex: true,
  }
}

///|
pub fn HtmlDocumentOptions::empty() -> HtmlDocumentOptions {
  { doctype: None, charset: None, viewport: None, enable_katex: false }
}

///|
fn compile_html_document(
  nodes : Array[Node],
  options : HtmlDocumentOptions,
) -> Result[String, Diagnostic] {
  let env : Array[Binding] = []
  let meta_attrs : Array[Attr] = []
  let explicit_head : Array[HtmlNode] = []
  let body : Array[HtmlNode] = []
  let inline_run : Array[HtmlNode] = []
  prebind_direct_templates(env, nodes)
  for node in nodes {
    match node {
      Let(name, value, _) => bind_value(env, name, value)
      Def(name, params, body, _) => bind_template(env, name, params, body)
      Meta(attrs, _) =>
        for attr in attrs {
          meta_attrs.push(attr)
          bind_meta_attr(env, attr)
        }
      HtmlHead(_, children, _) =>
        match compile_node_sequence(children, env, 1, false, false) {
          Err(error) => return Err(error)
          Ok(compiled) =>
            for child in compiled {
              explicit_head.push(child)
            }
        }
      _ =>
        match compile_node(node, env, 1, false) {
          Err(error) => return Err(error)
          Ok(compiled) =>
            for html_node in compiled {
              append_compiled_node(inline_run, body, html_node, true)
            }
        }
    }
  }
  flush_paragraph(inline_run, body)
  let html_attrs = match html_document_attrs(meta_attrs, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let head = match html_head_nodes(meta_attrs, explicit_head, env, options) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let document = HtmlNode::Element("html", html_attrs, [
    HtmlNode::Element("head", [], head),
    HtmlNode::Element("body", [], body),
  ])
  Ok(render_html_document(document, options.doctype))
}

///|
fn render_html_document(document : HtmlNode, doctype : String?) -> String {
  match document {
    HtmlNode::Element(
      "html",
      attrs,
      [HtmlNode::Element("head", _, head), HtmlNode::Element("body", _, body)]
    ) => {
      let lines : Array[String] = []
      match doctype {
        Some(value) => lines.push("<!DOCTYPE \{value}>")
        None => ()
      }
      lines.push(render_open_tag("html", attrs))
      lines.push("  <head>")
      push_rendered_lines(lines, head, "    ")
      lines.push("  </head>")
      lines.push("  <body>")
      push_rendered_lines(lines, body, "    ")
      lines.push("  </body>")
      lines.push("</html>")
      lines.join("\n")
    }
    _ =>
      render_doctype(doctype) +
      @sexp.render_html_with([document], render_custom_node)
  }
}

///|
fn push_rendered_lines(
  lines : Array[String],
  nodes : Array[HtmlNode],
  indent : String,
) -> Unit {
  for node in nodes {
    let rendered = @sexp.render_html_with([node], render_custom_node)
    for line in rendered.split("\n") {
      if line.length() > 0 {
        lines.push(indent + line.to_owned())
      }
    }
  }
}

///|
fn render_open_tag(tag : String, attrs : Array[(String, String?)]) -> String {
  let rendered = @sexp.render_html_with(
    [HtmlNode::Element(tag, attrs, [])],
    render_custom_node,
  )
  let suffix = "</" + tag + ">"
  if rendered.has_suffix(suffix) {
    rendered.unsafe_substring(start=0, end=rendered.length() - suffix.length())
  } else {
    rendered
  }
}

///|
fn html_document_attrs(
  meta_attrs : Array[Attr],
  env : Array[Binding],
) -> Result[Array[(String, String?)], Diagnostic] {
  let attrs : Array[(String, String?)] = []
  for attr in meta_attrs {
    if is_html_document_attr(attr.name) {
      match attr.value {
        Some(value) =>
          match value_to_scalar(value, env) {
            Ok(text) => set_attr(attrs, attr.name, Some(text))
            Err(error) => return Err(error)
          }
        None => ()
      }
    }
  }
  Ok(attrs)
}

///|
fn is_html_document_attr(name : String) -> Bool {
  name == "lang" || name == "dir"
}

///|
fn html_head_nodes(
  meta_attrs : Array[Attr],
  explicit_head : Array[HtmlNode],
  env : Array[Binding],
  options : HtmlDocumentOptions,
) -> Result[Array[HtmlNode], Diagnostic] {
  let head : Array[HtmlNode] = []
  match meta_scalar_or_default(meta_attrs, "charset", options.charset, env) {
    Ok(Some(text)) =>
      head.push(HtmlNode::Element("meta", [("charset", Some(text))], []))
    Ok(None) => ()
    Err(error) => return Err(error)
  }
  match meta_scalar_or_default(meta_attrs, "viewport", options.viewport, env) {
    Ok(Some(text)) => head.push(html_named_meta("viewport", text))
    Ok(None) => ()
    Err(error) => return Err(error)
  }
  match push_optional_head_meta(head, meta_attrs, env) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if options.enable_katex {
    head.push(raw_html_node(HTML_IMPORT_KATEX))
  }
  append_html_nodes(head, explicit_head)
  Ok(head)
}

///|
fn push_optional_head_meta(
  head : Array[HtmlNode],
  meta_attrs : Array[Attr],
  env : Array[Binding],
) -> Result[Unit, Diagnostic] {
  push_optional_meta_node(head, meta_attrs, "title", env, text => {
    HtmlNode::Element("title", [], [HtmlNode::Text(text)])
  })
  .bind(_ => {
    push_optional_meta_node(head, meta_attrs, "description", env, text => {
      html_named_meta("description", text)
    })
  })
  .bind(_ => {
    push_optional_meta_node(head, meta_attrs, "author", env, text => {
      html_named_meta("author", text)
    })
  })
}

///|
fn push_optional_meta_node(
  head : Array[HtmlNode],
  meta_attrs : Array[Attr],
  name : String,
  env : Array[Binding],
  make_node : (String) -> HtmlNode,
) -> Result[Unit, Diagnostic] {
  match meta_scalar(meta_attrs, name, env) {
    Ok(Some(text)) => {
      head.push(make_node(text))
      Ok(())
    }
    Ok(None) => Ok(())
    Err(error) => Err(error)
  }
}

///|
fn meta_scalar_or_default(
  meta_attrs : Array[Attr],
  key : String,
  default : String?,
  env : Array[Binding],
) -> Result[String?, Diagnostic] {
  match meta_scalar(meta_attrs, key, env) {
    Ok(Some(text)) => Ok(Some(text))
    Ok(None) => Ok(default)
    Err(error) => Err(error)
  }
}

///|
fn meta_scalar(
  meta_attrs : Array[Attr],
  key : String,
  env : Array[Binding],
) -> Result[String?, Diagnostic] {
  let mut found : String? = None
  for attr in meta_attrs {
    if attr.name == key {
      match attr.value {
        Some(value) =>
          match value_to_scalar(value, env) {
            Ok(text) => found = Some(text)
            Err(error) => return Err(error)
          }
        None => ()
      }
    }
  }
  Ok(found)
}

///|
fn render_doctype(doctype : String?) -> String {
  match doctype {
    Some(value) => "<!DOCTYPE " + value + ">"
    None => ""
  }
}

///|
fn html_named_meta(name : String, content : String) -> HtmlNode {
  HtmlNode::Element(
    "meta",
    [("name", Some(name)), ("content", Some(content))],
    [],
  )
}

///|
fn set_attr(
  attrs : Array[(String, String?)],
  name : String,
  value : String?,
) -> Unit {
  for i in 0..<attrs.length() {
    match attrs[i] {
      (existing, _) if existing == name => {
        attrs[i] = (name, value)
        return
      }
      _ => ()
    }
  }
  attrs.push((name, value))
}
