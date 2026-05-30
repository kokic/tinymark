///|
fn render_html_result(source : String) -> Result[String, String] {
  match altsia_to_html(source) {
    Ok(html) => Ok(html)
    Err(diagnostic) => Err(diagnostic.render())
  }
}

///|
fn render_html_document_result(
  source : String,
  options? : HtmlDocumentOptions,
) -> Result[String, String] {
  match options {
    Some(options) =>
      match altsia_to_html_document(source, options~) {
        Ok(html) => Ok(html)
        Err(diagnostic) => Err(diagnostic.render())
      }
    None =>
      match altsia_to_html_document(source) {
        Ok(html) => Ok(html)
        Err(diagnostic) => Err(diagnostic.render())
      }
  }
}

///|
test "renders paragraphs and inline sugar" {
  let input =
    #|Hello *world*.
    #|Still same paragraph.
    #|
    #|Next **one**.
  let expected = "<p>Hello <em>world</em>.Still same paragraph.</p><p>Next <strong>one</strong>.</p>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "preserves spaces around inline sexp" {
  let input = "Open (span your) eyes."
  let expected = "<p>Open <span>your</span> eyes.</p>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "converts smart dashes in text" {
  @test.assert_eq(
    render_html_result("a -- b --- c *x -- y --- z*"),
    Ok("<p>a – b — c <em>x – y — z</em></p>"),
  )
}

///|
test "does not convert dashes in raw strings or attributes" {
  @test.assert_eq(
    render_html_result("(span (:data `a---b--c`) `x---y--z`)"),
    Ok("<p><span data=\"a---b--c\">x---y--z</span></p>"),
  )
}

///|
test "def references and interpolated attributes" {
  let input = "(let lang `zh`)(let base `/docs`)(p (:class \"doc-(lang)\") (a (:href \"(base)/intro\") \"语言：(lang)\"))"
  let expected = "<p class=\"doc-zh\"><a href=\"/docs/intro\">语言：zh</a></p>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "unknown zero arg sexp is empty tag but bound name expands" {
  let input = "(let x (em yes))(p (x)(em))"
  let expected = "<p><em>yes</em><em></em></p>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "section title and local condition" {
  let input = "(section (:title \"Intro\") (let draft true)(when (draft) (note draft)))"
  let expected = "<section><h1>Intro</h1><aside class=\"note\"><p>draft</p></aside></section>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "mixed block keeps simple nested text unwrapped" {
  let input =
    #|(block
    #|Nested line one
    #|Nested line two)
  let expected = "<div>Nested line oneNested line two</div>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "mixed block wraps paragraphs only when needed" {
  let input =
    #|(block
    #|First paragraph.
    #|
    #|Second paragraph.)
  let expected = "<div><p>First paragraph.</p><p>Second paragraph.</p></div>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "mixed block wraps paragraphs only when needed #2" {
  let input =
    #|(block
    #|First paragraph.
    #|  
    #|Second paragraph.)
  let expected = "<div><p>First paragraph.</p><p>Second paragraph.</p></div>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "mixed block detects paragraph need through local refs" {
  let input =
    #|(block
    #|  (let body `First.
    #|
    #|Second.`)
    #|  (body))
  let expected = "<div><p>First.</p><p>Second.</p></div>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "template supports positional and named arguments" {
  let input =
    #|(def reorder (x y z) (p (z) (y) (x)))
    #|(reorder (:y `Y`) `X` `Z`)
  let expected = "<p>Z Y X</p>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "template supports fragments and attributes" {
  let input =
    #|(def badge (kind body)
    #|  (span (:class "badge badge-(kind)") (body)))
    #|(badge (:kind `info`) (em Careful))
  let expected = "<p><span class=\"badge badge-info\"><em>Careful</em></span></p>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "underscore groups multiple values as one template argument" {
  let input =
    #|(def joined (body) (p (body)))
    #|(joined (_ "a" "b" "c"))
  let expected = "<p>a b c</p>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "underscore does not render a wrapper tag" {
  @test.assert_eq(render_html_result("(_ (em a) b)"), Ok("<p><em>a</em> b</p>"))
}

///|
test "template definitions are hoisted within the same scope" {
  let input =
    #|(card Hello)
    #|(def card (body) (p (body)))
  @test.assert_eq(render_html_result(input), Ok("<p>Hello</p>"))
}

///|
test "template hoisting does not cross child scopes" {
  let input =
    #|(section (:title "Outer")
    #|  (section (:title "Inner")
    #|    (def card (body) (p (body))))
    #|  (card Hello))
  let expected = "<section><h1>Outer</h1><section><h2>Inner</h2></section><p><card>Hello</card></p></section>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "template reports argument errors" {
  let unknown_arg =
    #|template error at line 1, column 20: unknown template argument: missing
    #|1 | (def t (x) (x))(t (:missing nope))
    #|  |                    ^
  let too_many_args =
    #|template error at line 1, column 28: too many template arguments
    #|1 | (def t (x) (x))(t (:x one) two)
    #|  |                            ^
  let duplicate_arg =
    #|template error at line 1, column 27: duplicate template argument: x
    #|1 | (def t (x) (x))(t (:x one :x two))
    #|  |                           ^
  let missing_arg =
    #|template error at line 1, column 19: missing template argument: y
    #|1 | (def t (x y) (x))(t one)
    #|  |                   ^
  let missing_arg_text_run =
    #|template error at line 1, column 19: missing template argument: y
    #|1 | (def t (x y) (x))(t one two)
    #|  |                   ^
  @test.assert_eq(
    render_html_result("(def t (x) (x))(t (:missing nope))"),
    Err(unknown_arg),
  )
  @test.assert_eq(
    render_html_result("(def t (x) (x))(t (:x one) two)"),
    Err(too_many_args),
  )
  @test.assert_eq(
    render_html_result("(def t (x) (x))(t (:x one :x two))"),
    Err(duplicate_arg),
  )
  @test.assert_eq(
    render_html_result("(def t (x y) (x))(t one)"),
    Err(missing_arg),
  )
  @test.assert_eq(
    render_html_result("(def t (x y) (x))(t one two)"),
    Err(missing_arg_text_run),
  )
}

///|
test "syntax errors include source location" {
  let expected =
    #|syntax error at line 2, column 1: unexpected ')'
    #|2 | )
    #|  | ^
  @test.assert_eq(render_html_result("first\n)"), Err(expected))
}

///|
test "list item syntax errors keep original location" {
  let expected =
    #|syntax error at line 2, column 3: unexpected ')'
    #|2 | )
    #|  | ^
  @test.assert_eq(render_html_result("- ok\n- )"), Err(expected))
}

///|
test "compile errors include source location" {
  let input =
    #|(let label (em hot))
    #|(span (:class (label)) Sale)
  let expected =
    #|type error at line 1, column 12: expected scalar value, but got rich content
    #|1 | (let label (em hot))
    #|  |            ^
  @test.assert_eq(render_html_result(input), Err(expected))
}

///|
test "plain text errors include source location" {
  let expected =
    #|content model error at line 1, column 13: expected plain text content
    #|1 | (codeblock (em js))
    #|  |             ^
  @test.assert_eq(render_html_result("(codeblock (em js))"), Err(expected))
}

///|
test "structural nesting does not wrap table cells in paragraphs" {
  let input = "(table (tbody (tr (td A) (td B))))"
  let expected = "<table><tbody><tr><td>A</td> <td>B</td></tr></tbody></table>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "html code tag remains inline" {
  let input = "Use (code cargo test)."
  let expected = "<p>Use <code>cargo test</code>.</p>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "list sugar and block quote codeblock" {
  let input =
    #|- one
    #|- two
    #|
    #|(codeblock (:lang `js`))
    #|```
    #|console.log(1)
    #|```
  let expected = "<ul><li>one</li><li>two</li></ul><pre><code class=\"lang-js\">console.log(1)\n</code></pre>"
  @test.assert_eq(render_html_result(input), Ok(expected))
}

///|
test "dash tag aliases item" {
  let input = "(list (- one) (- two))"
  let expected = "<ul><li>one</li> <li>two</li></ul>"
  @test.assert_eq(render_html_result(input), Ok(expected))
  @test.assert_eq(
    render_html_result(input),
    render_html_result("(list (item one) (item two))"),
  )
}

///|
test "html scoped style supports pseudo classes" {
  let input =
    #|(html.head
    #|  (html.style (:scope `article`)
    #|    (& (:max-width `68ch`))
    #|    (&:hover (:color `red`))
    #|    (a:hover (:text-decoration `underline`))
    #|    (.lead::first-line (:font-weight `700`))
    #|    (h1 (:margin `0`))
    #|    (h2:focus-within (:color `blue`))))
    #|(block (:class `article`) Body)
  let expected =
    #|<html>
    #|  <head>
    #|    <style>.article{max-width:68ch;}.article:hover{color:red;}.article a:hover{text-decoration:underline;}.article .lead::first-line{font-weight:700;}.article h1{margin:0;}.article h2:focus-within{color:blue;}</style>
    #|  </head>
    #|  <body>
    #|    <div class="article">Body</div>
    #|  </body>
    #|</html>
  @test.assert_eq(
    render_html_document_result(input, options=HtmlDocumentOptions::empty()),
    Ok(expected),
  )
}

///|
test "html style without scope remains global" {
  let input =
    #|(html.head
    #|  (html.style
    #|    (body (:margin `0`))
    #|    (a:hover (:color `red`))))
    #|Body
  let expected =
    #|<html>
    #|  <head>
    #|    <style>body{margin:0;}a:hover{color:red;}</style>
    #|  </head>
    #|  <body>
    #|    <p>Body</p>
    #|  </body>
    #|</html>
  @test.assert_eq(
    render_html_document_result(input, options=HtmlDocumentOptions::empty()),
    Ok(expected),
  )
}

///|
test "html style rejects selector escape hatch" {
  let input = "(html.style (rule (:selector `h1` :margin `0`)))"
  let expected =
    #|content model error at line 1, column 14: css rule form is not supported yet
    #|1 | (html.style (rule (:selector `h1` :margin `0`)))
    #|  |              ^
  @test.assert_eq(render_html_result(input), Err(expected))
}

///|
test "html document uses altsia meta and explicit html head" {
  let input =
    #|(meta 
    #|  ( :title "Doc" 
    #|    :lang `zh-CN` 
    #|    :dir `ltr` 
    #|    :description "Desc" 
    #|    :author "Ada"))
    #|(html.head
    #|  (link (:rel `stylesheet` :href `/style.css`))
    #|  (script (:type `module` :src `/main.js`)))
    #|
    #|Hello (title).
  let expected =
    #|<html lang="zh-CN" dir="ltr">
    #|  <head>
    #|    <title>Doc</title>
    #|    <meta name="description" content="Desc">
    #|    <meta name="author" content="Ada">
    #|    <link rel="stylesheet" href="/style.css">
    #|    <script type="module" src="/main.js"></script>
    #|  </head>
    #|  <body>
    #|    <p>Hello Doc.</p>
    #|  </body>
    #|</html>
  @test.assert_eq(
    render_html_document_result(input, options=HtmlDocumentOptions::empty()),
    Ok(expected),
  )
}

///|
test "html document uses backend defaults" {
  let input = "(meta (:title \"Doc\"))Body"
  let expected =
    #|<!DOCTYPE html>
    #|<html>
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Doc</title>
    #|  </head>
    #|  <body>
    #|    <p>Body</p>
    #|  </body>
    #|</html>
  @test.assert_eq(
    render_html_document_result(input, options={
      doctype: Some("html"),
      charset: Some("utf-8"),
      viewport: Some("width=device-width, initial-scale=1"),
      enable_katex: false,
    }),
    Ok(expected),
  )
}

///|
test "html meta overrides backend defaults" {
  let input = "(meta (:charset `shift_jis` :viewport `custom`))Body"
  let expected =
    #|<!DOCTYPE html>
    #|<html>
    #|  <head>
    #|    <meta charset="shift_jis">
    #|    <meta name="viewport" content="custom">
    #|  </head>
    #|  <body>
    #|    <p>Body</p>
    #|  </body>
    #|</html>
  @test.assert_eq(
    render_html_document_result(input, options={
      doctype: Some("html"),
      charset: Some("utf-8"),
      viewport: Some("width=device-width, initial-scale=1"),
      enable_katex: false,
    }),
    Ok(expected),
  )
}

///|
test "html document appends katex imports when enabled" {
  let input = "(meta (:title \"Math\"))$x$"
  @test.assert_eq(
    render_html_document_result(input).map(html => {
      html.contains("katex.min.css") &&
      html.contains("renderMathInElement(document.body")
    }),
    Ok(true),
  )
}

///|
test "html head is ignored by fragment output" {
  let input = "(html.head (title Hidden))Visible"
  @test.assert_eq(render_html_result(input), Ok("<p>Visible</p>"))
}
