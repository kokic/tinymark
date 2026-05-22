///|
const TAG_RAW_HTML = "html-raw"

///|
fn raw_html_node(html : String) -> HtmlNode {
  HtmlNode::Element(TAG_RAW_HTML, [], [HtmlNode::Text(html)])
}
