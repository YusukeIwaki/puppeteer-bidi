# frozen_string_literal: true

require "test_helper"

test(['QueryHandler', 'Text selectors', 'in Page', 'should query existing element'].join(" ")) do |page:|
  page.set_content('<section>test</section>')

  expect(page.query_selector('text/test')).not_to be_nil
  expect(page.query_selector_all('text/test').length).to eq(1)
end

test(['QueryHandler', 'Text selectors', 'in Page', 'should return empty array for non-existing element'].join(" ")) do |page:|
  expect(page.query_selector('text/test')).to be_nil
  expect(page.query_selector_all('text/test').length).to eq(0)
end

test(['QueryHandler', 'Text selectors', 'in Page', 'should return first element'].join(" ")) do |page:|
  page.set_content('<div id="1">a</div> <div>a</div>')

  element = page.query_selector('text/a')
  id = element.evaluate('e => e.id')
  expect(id).to eq('1')
end

test(['QueryHandler', 'Text selectors', 'in Page', 'should return multiple elements'].join(" ")) do |page:|
  page.set_content('<div>a</div> <div>a</div>')

  elements = page.query_selector_all('text/a')
  expect(elements.length).to eq(2)
end

test(['QueryHandler', 'Text selectors', 'in Page', 'should pierce shadow DOM'].join(" ")) do |page:|
  page.evaluate(<<~JS)
    () => {
      const div = document.createElement('div');
      const shadow = div.attachShadow({mode: 'open'});
      const diva = document.createElement('div');
      shadow.append(diva);
      const divb = document.createElement('div');
      shadow.append(divb);
      diva.innerHTML = 'a';
      divb.innerHTML = 'b';
      document.body.append(div);
    }
  JS

  element = page.query_selector('text/a')
  text_content = element.evaluate('e => e.textContent')
  expect(text_content).to eq('a')
end

test(['QueryHandler', 'Text selectors', 'in Page', 'should query deeply nested text'].join(" ")) do |page:|
  page.set_content(<<~HTML)
    <div>
      <div>a</div>
      <div>b</div>
    </div>
  HTML

  element = page.query_selector('text/a')
  text_content = element.evaluate('e => e.textContent')
  expect(text_content).to eq('a')
end

test(['QueryHandler', 'Text selectors', 'in Page', 'should query inputs'].join(" ")) do |page:|
  page.set_content('<input value="a" />')

  element = page.query_selector('text/a')
  value = element.evaluate('e => e.value')
  expect(value).to eq('a')
end

test(['QueryHandler', 'Text selectors', 'in Page', 'should not query radio'].join(" ")) do |page:|
  page.set_content('<radio value="a"></radio>')

  expect(page.query_selector('text/a')).to be_nil
end

test(['QueryHandler', 'Text selectors', 'in Page', 'should query text spanning multiple elements'].join(" ")) do |page:|
  page.set_content('<div><span>a</span> <span>b</span></div>')

  element = page.query_selector('text/a b')
  text_content = element.evaluate('e => e.textContent')
  expect(text_content).to eq('a b')
end

test(['QueryHandler', 'Text selectors', 'in Page', 'should clear caches'].join(" ")) do |page:|
  page.set_content(<<~HTML)
    <div id="target1">text</div>
    <input id="target2" value="text" />
    <div id="target3">text</div>
  HTML

  div = page.query_selector('#target1')
  input = page.query_selector('#target2')

  div.evaluate('div => { div.textContent = "text" }')
  expect(page.eval_on_selector('text/text', 'e => e.id')).to eq('target1')

  div.evaluate('div => { div.textContent = "foo" }')
  expect(page.eval_on_selector('text/text', 'e => e.id')).to eq('target2')

  input.evaluate('input => { input.value = "" }')
  input.type('foo')
  expect(page.eval_on_selector('text/text', 'e => e.id')).to eq('target3')

  div.evaluate('div => { div.textContent = "text" }')
  input.evaluate('input => { input.value = "" }')
  input.type('text')
  expect(page.eval_on_selector_all('text/text', 'es => es.length')).to eq(3)

  div.evaluate('div => { div.textContent = "foo" }')
  expect(page.eval_on_selector_all('text/text', 'es => es.length')).to eq(2)

  input.evaluate('input => { input.value = "" }')
  input.type('foo')
  expect(page.eval_on_selector_all('text/text', 'es => es.length')).to eq(1)
end

test(['QueryHandler', 'Text selectors', 'in ElementHandles', 'should query existing element'].join(" ")) do |page:|
  page.set_content('<div class="a"><span>a</span></div>')

  element_handle = page.query_selector('div')
  expect(element_handle.query_selector('text/a')).not_to be_nil
  expect(element_handle.query_selector_all('text/a').length).to eq(1)
end

test(['QueryHandler', 'Text selectors', 'in ElementHandles', 'should return null for non-existing element'].join(" ")) do |page:|
  page.set_content('<div class="a"></div>')

  element_handle = page.query_selector('div')
  expect(element_handle.query_selector('text/a')).to be_nil
  expect(element_handle.query_selector_all('text/a').length).to eq(0)
end

test(['QueryHandler', 'XPath selectors', 'in Page', 'should query existing element'].join(" ")) do |page:|
  page.set_content('<section>test</section>')

  element = page.query_selector('xpath/html/body/section')
  expect(element).not_to be_nil

  elements = page.query_selector_all('xpath/html/body/section')
  expect(elements.length).to eq(1)
end

test(['QueryHandler', 'XPath selectors', 'in Page', 'should return empty array for non-existing element'].join(" ")) do |page:|
  element = page.query_selector('xpath/html/body/non-existing-element')
  expect(element).to be_nil

  elements = page.query_selector_all('xpath/html/body/non-existing-element')
  expect(elements.length).to eq(0)
end

test(['QueryHandler', 'XPath selectors', 'in Page', 'should return first element'].join(" ")) do |page:|
  page.set_content('<div>a</div> <div></div>')

  element = page.query_selector('xpath/html/body/div')
  expect(element).not_to be_nil

  text_matches = element.evaluate('e => e.textContent === "a"')
  expect(text_matches).to eq(true)
end

test(['QueryHandler', 'XPath selectors', 'in Page', 'should return multiple elements'].join(" ")) do |page:|
  page.set_content('<div></div> <div></div>')

  elements = page.query_selector_all('xpath/html/body/div')
  expect(elements.length).to eq(2)
end

test(['QueryHandler', 'XPath selectors', 'in ElementHandles', 'should query existing element'].join(" ")) do |page:|
  page.set_content('<div class="a">a<span></span></div>')

  element_handle = page.query_selector('div')
  expect(element_handle).not_to be_nil

  span = element_handle.query_selector('xpath/span')
  expect(span).not_to be_nil

  spans = element_handle.query_selector_all('xpath/span')
  expect(spans.length).to eq(1)
end

test(['QueryHandler', 'XPath selectors', 'in ElementHandles', 'should return null for non-existing element'].join(" ")) do |page:|
  page.set_content('<div class="a">a</div>')

  element_handle = page.query_selector('div')
  expect(element_handle).not_to be_nil

  span = element_handle.query_selector('xpath/span')
  expect(span).to be_nil

  spans = element_handle.query_selector_all('xpath/span')
  expect(spans.length).to eq(0)
end
