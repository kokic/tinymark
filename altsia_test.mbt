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

///|
test "html document uses altsia meta and explicit html head" {
  let input =
    #|(meta (:title "Doc" :lang `zh` :charset `utf-8` :viewport `width=device-width` :description "Desc" :author "Ada"))
    #|(html.head
    #|  (link (:rel `stylesheet` :href `/style.css`))
    #|  (script (:type `module` :src `/main.js`)))
    #|
    #|Hello (title).
  let expected = "<!DOCTYPE html><html lang=\"zh\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>Doc</title><meta name=\"description\" content=\"Desc\"><meta name=\"author\" content=\"Ada\"><link rel=\"stylesheet\" href=\"/style.css\"><script type=\"module\" src=\"/main.js\"></script></head><body><p>Hello Doc.</p></body></html>"
  @test.assert_eq(altsia_to_html_document(input), Ok(expected))
}

///|
test "html head is ignored by fragment output" {
  let input = "(html.head (title Hidden))Visible"
  @test.assert_eq(altsia_to_html(input), Ok("<p>Visible</p>"))
}
