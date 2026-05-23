///|
test "renders paragraphs and inline sugar" {
  let input =
    #|Hello *world*.
    #|Still same paragraph.
    #|
    #|Next **one**.
  let expected = "<p>Hello <em>world</em>.Still same paragraph.</p><p>Next <strong>one</strong>.</p>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "def references and interpolated attributes" {
  let input = "(let lang `zh`)(let base `/docs`)(p (:class \"doc-(lang)\") (a (:href \"(base)/intro\") \"语言：(lang)\"))"
  let expected = "<p class=\"doc-zh\"><a href=\"/docs/intro\">语言：zh</a></p>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "unknown zero arg sexp is empty tag but bound name expands" {
  let input = "(let x (em yes))(p (x)(em))"
  let expected = "<p><em>yes</em><em></em></p>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "section title and local condition" {
  let input = "(section (:title \"Intro\") (let draft true)(when (draft) (note draft)))"
  let expected = "<section><h1>Intro</h1><aside class=\"note\"><p>draft</p></aside></section>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "mixed block keeps simple nested text unwrapped" {
  let input =
    #|(block
    #|Nested line one
    #|Nested line two)
  let expected = "<div>Nested line oneNested line two</div>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "mixed block wraps paragraphs only when needed" {
  let input =
    #|(block
    #|First paragraph.
    #|
    #|Second paragraph.)
  let expected = "<div><p>First paragraph.</p><p>Second paragraph.</p></div>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
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
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "template supports positional and named arguments" {
  let input =
    #|(def reorder (x y z) (p (z) (y) (x)))
    #|(reorder (:y `Y`) X Z)
  let expected = "<p>ZYX</p>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "template supports fragments and attributes" {
  let input =
    #|(def badge (kind body)
    #|  (span (:class "badge badge-(kind)") (body)))
    #|(badge (:kind `info`) (em Careful))
  let expected = "<p><span class=\"badge badge-info\"><em>Careful</em></span></p>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "template reports argument errors" {
  @test.assert_eq(
    altsia_to_html("(def t (x) (x))(t (:missing nope))"),
    Err("unknown template argument: missing"),
  )
  @test.assert_eq(
    altsia_to_html("(def t (x) (x))(t (:x one) two)"),
    Err("too many template arguments"),
  )
  @test.assert_eq(
    altsia_to_html("(def t (x) (x))(t (:x one :x two))"),
    Err("duplicate template argument: x"),
  )
  @test.assert_eq(
    altsia_to_html("(def t (x y) (x))(t one)"),
    Err("missing template argument: y"),
  )
}

///|
test "structural nesting does not wrap table cells in paragraphs" {
  let input = "(table (tbody (tr (td A) (td B))))"
  let expected = "<table><tbody><tr><td>A</td><td>B</td></tr></tbody></table>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "html code tag remains inline" {
  let input = "Use (code cargo test)."
  let expected = "<p>Use <code>cargo test</code>.</p>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
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
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "html document uses altsia meta and explicit html head" {
  let input =
    #|(meta 
    #|  ( :title "Doc" 
    #|    :lang `zh` 
    #|    :description "Desc" 
    #|    :author "Ada"))
    #|(html.head
    #|  (link (:rel `stylesheet` :href `/style.css`))
    #|  (script (:type `module` :src `/main.js`)))
    #|
    #|Hello (title).
  let expected =
    #|<html lang="zh">
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
    altsia_to_html_document(input, options=HtmlDocumentOptions::empty()),
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
    altsia_to_html_document(input, options={
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
    altsia_to_html_document(input, options={
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
    altsia_to_html_document(input).map(html => {
      html.contains("katex.min.css") &&
      html.contains("renderMathInElement(document.body")
    }),
    Ok(true),
  )
}

///|
test "html head is ignored by fragment output" {
  let input = "(html.head (title Hidden))Visible"
  @test.assert_eq(altsia_to_html(input), Ok("<p>Visible</p>"))
}
