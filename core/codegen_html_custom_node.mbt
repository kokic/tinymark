///|
fn render_custom_node(node : @sexp.SexpNode) -> String? {
  match node {
    HtmlNode::Element(tag, _, [HtmlNode::Text(html)]) if tag == TAG_RAW_HTML =>
      Some(html)
    _ => None
  }
}
