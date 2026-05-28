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
          Ok(compiled) => explicit_head.append(compiled)
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
  Ok(@sexp.render_html_document(html_attrs, head, body, options.doctype))
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
            Ok(text) => @sexp.upsert_attr(attrs, attr.name, Some(text))
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
    head.push(HtmlNode::RawHtml(HTML_IMPORT_KATEX))
  }
  head.append(explicit_head)
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
fn html_named_meta(name : String, content : String) -> HtmlNode {
  HtmlNode::Element(
    "meta",
    [("name", Some(name)), ("content", Some(content))],
    [],
  )
}
