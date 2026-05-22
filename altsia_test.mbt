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
  let input = "(def lang `zh`)(def base `/docs`)(p (:class \"doc-(lang)\") (a (:href \"(base)/intro\") \"语言：(lang)\"))"
  let expected = "<p class=\"doc-zh\"><a href=\"/docs/intro\">语言：zh</a></p>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "unknown zero arg sexp is empty tag but bound name expands" {
  let input = "(def x (em yes))(p (x)(em))"
  let expected = "<p><em>yes</em><em></em></p>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "section title and local condition" {
  let input = "(section (:title \"Intro\") (def draft true)(when (draft) (note draft)))"
  let expected = "<section><h1>Intro</h1><aside class=\"note\"><p>draft</p></aside></section>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}

///|
test "list sugar and block quote code" {
  let input = 
  #|- one
  #|- two
  #|
  #|(code (:lang `js`))
  #|```
  #|console.log(1)
  #|```
  let expected = "<ul><li>one</li><li>two</li></ul><pre><code class=\"lang-js\">console.log(1)\n</code></pre>"
  @test.assert_eq(altsia_to_html(input), Ok(expected))
}
