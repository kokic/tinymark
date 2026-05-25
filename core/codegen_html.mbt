///|
type HtmlNode = @sexp.SexpNode

///|
priv enum ContentModel {
  InlineOnly
  BlockFlow
  MixedFlow
}

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
    value: BindingValue::BoundTemplate({ params, body, env: clone_env(env) }),
  })
}

///|
fn bind_meta_attr(env : Array[Binding], attr : Attr) -> Unit {
  match attr.value {
    Some(value) => bind_value(env, attr.name, value)
    None => ()
  }
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
fn append_bindings(out : Array[Binding], bindings : Array[Binding]) -> Unit {
  for binding in bindings {
    out.push(binding)
  }
}

///|
fn append_html_nodes(out : Array[HtmlNode], nodes : Array[HtmlNode]) -> Unit {
  for node in nodes {
    out.push(node)
  }
}

///|
fn append_compiled_node(
  inline_run : Array[HtmlNode],
  out : Array[HtmlNode],
  node : HtmlNode,
  wrap_paragraphs : Bool,
) -> Unit {
  if wrap_paragraphs && is_inline_html_node(node) {
    append_with_paragraph_splits(inline_run, out, node)
  } else {
    flush_paragraph(inline_run, out)
    out.push(node)
  }
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
    HtmlNode::Text(text) if has_paragraph_break(text) =>
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
    let break_end = paragraph_break_end(chars, index)
    if break_end >= 0 {
      if index > start {
        inline_run.push(
          HtmlNode::Text(String::from_array(chars.view(start~, end=index))),
        )
      }
      flush_paragraph(inline_run, out)
      index = break_end
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
fn has_paragraph_break(text : String) -> Bool {
  let chars = text.to_array()
  let mut index = 0
  while index < chars.length() {
    if paragraph_break_end(chars, index) >= 0 {
      return true
    }
    index += 1
  }
  false
}

///|
fn paragraph_break_end(chars : Array[Char], index : Int) -> Int {
  if chars[index] != '\n' {
    return -1
  }
  let mut scan = index + 1
  while scan < chars.length() && is_blank_line_space(chars[scan]) {
    scan += 1
  }
  if scan < chars.length() && chars[scan] == '\n' {
    scan + 1
  } else {
    -1
  }
}

///|
fn is_blank_line_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\r'
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
  tag == "div" ||
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
