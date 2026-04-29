# frozen_string_literal: true

require "test_helper"

def wait_for_frame(page, timeout: 2)
  deadline = Time.now + timeout
  loop do
    frame = page.frames.find { |candidate| yield candidate }
    return frame if frame
    raise "Frame not found" if Time.now > deadline
    sleep 0.05
  end
end

test(["Locator", "should work with a frame"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button onclick="this.innerText = 'clicked';">test</button>
  HTML
  will_click = false
  page.main_frame
    .locator("button")
    .on(Puppeteer::Bidi::LocatorEvent::ACTION) { will_click = true }
    .click
  button = page.query_selector("button")
  text = button&.evaluate("el => el.innerText")
  expect(text).to eq("clicked")
  expect(will_click).to eq(true)
ensure
  button&.dispose
end

test(["Locator", "should work without preconditions"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button onclick="this.innerText = 'clicked';">test</button>
  HTML
  will_click = false
  page
    .locator("button")
    .set_ensure_element_is_in_the_viewport(false)
    .set_timeout(0)
    .set_visibility(nil)
    .set_wait_for_enabled(false)
    .set_wait_for_stable_bounding_box(false)
    .on(Puppeteer::Bidi::LocatorEvent::ACTION) { will_click = true }
    .click
  button = page.query_selector("button")
  text = button&.evaluate("el => el.innerText")
  expect(text).to eq("clicked")
  expect(will_click).to eq(true)
ensure
  button&.dispose
end

test(["Locator", "Locator.click", "should work"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button onclick="this.innerText = 'clicked';">test</button>
  HTML
  will_click = false
  page
    .locator("button")
    .on(Puppeteer::Bidi::LocatorEvent::ACTION) { will_click = true }
    .click
  button = page.query_selector("button")
  text = button&.evaluate("el => el.innerText")
  expect(text).to eq("clicked")
  expect(will_click).to eq(true)
ensure
  button&.dispose
end

test(["Locator", "Locator.click", "should work for multiple selectors"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button onclick="this.innerText = 'clicked';">test</button>
  HTML
  clicked = false
  page
    .locator("::-p-text(test), ::-p-xpath(/button)")
    .on(Puppeteer::Bidi::LocatorEvent::ACTION) { clicked = true }
    .click
  button = page.query_selector("button")
  text = button&.evaluate("el => el.innerText")
  expect(text).to eq("clicked")
  expect(clicked).to eq(true)
ensure
  button&.dispose
end

test(["Locator", "Locator.click", "should work if the element is out of viewport"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button style="margin-top: 600px;" onclick="this.innerText = 'clicked';">
      test
    </button>
  HTML
  page.locator("button").click
  button = page.query_selector("button")
  text = button&.evaluate("el => el.innerText")
  expect(text).to eq("clicked")
ensure
  button&.dispose
end

test(["Locator", "Locator.click", "should work with element handles"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button style="margin-top: 600px;" onclick="this.innerText = 'clicked';">
      test
    </button>
  HTML
  button = page.query_selector("button")
  raise "button not found" unless button

  button.as_locator.click
  text = button.evaluate("el => el.innerText")
  expect(text).to eq("clicked")
ensure
  button&.dispose
end

test(["Locator", "Locator.click", "should work if the element becomes visible later"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button style="display: none;" onclick="this.innerText = 'clicked';">test</button>
  HTML
  button = page.query_selector("button")
  raise "button not found" unless button

  click_thread = Thread.new do
    page.locator("button").click
  end
  sleep 0.1
  expect(button.evaluate("el => el.innerText")).to eq("test")
  button.evaluate("el => { el.style.display = 'block'; }")
  click_thread.value
  expect(button.evaluate("el => el.innerText")).to eq("clicked")
ensure
  button&.dispose
end

test(["Locator", "Locator.click", "should work if the element becomes enabled later"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button disabled onclick="this.innerText = 'clicked';">test</button>
  HTML
  button = page.query_selector("button")
  raise "button not found" unless button

  click_thread = Thread.new do
    page.locator("button").click
  end
  sleep 0.1
  expect(button.evaluate("el => el.innerText")).to eq("test")
  button.evaluate("el => { el.disabled = false; }")
  click_thread.value
  expect(button.evaluate("el => el.innerText")).to eq("clicked")
ensure
  button&.dispose
end

test(["Locator", "Locator.click", "should work if multiple conditions are satisfied later"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content('<button style="margin-top: 600px; display: none;" disabled ' \
                   'onclick="this.innerText = \'clicked\';">test</button>')
  button = page.query_selector("button")
  raise "button not found" unless button

  click_thread = Thread.new do
    page.locator("button").click
  end
  sleep 0.1
  expect(button.evaluate("el => el.innerText")).to eq("test")
  button.evaluate("el => { el.disabled = false; el.style.display = 'block'; }")
  click_thread.value
  expect(button.evaluate("el => el.innerText")).to eq("clicked")
ensure
  button&.dispose
end

test(["Locator", "Locator.click", "should time out"].join(" ")) do |page:|
  page.set_default_timeout(200)
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button style="display: none;" onclick="this.innerText = 'clicked';">
      test
    </button>
  HTML
  expect do
    page.locator("button").click
  end.to raise_error(Puppeteer::Bidi::TimeoutError, /Timed out after waiting 200ms/)
end

test(["Locator", "Locator.click", "should retry clicks on errors"].join(" ")) do |page:|
  page.set_default_timeout(200)
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button style="display: none;" onclick="this.innerText = 'clicked';">
      test
    </button>
  HTML
  expect do
    page.locator("button").click
  end.to raise_error(Puppeteer::Bidi::TimeoutError, /Timed out after waiting 200ms/)
end

test(["Locator", "Locator.click", "can be aborted"].join(" ")) do
  skip "Abort signals are not implemented for locator actions in Ruby yet."
end

test(["Locator", "Locator.click", "should work with an iframe"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <iframe
      src="data:text/html,<button onclick=&quot;this.innerText = 'clicked';&quot;>test</button>"
    ></iframe>
  HTML
  frame = wait_for_frame(page) { |candidate| candidate.url.to_s.start_with?("data") }
  will_click = false
  frame
    .locator("button")
    .on(Puppeteer::Bidi::LocatorEvent::ACTION) { will_click = true }
    .click
  button = frame.query_selector("button")
  text = button&.evaluate("el => el.innerText")
  expect(text).to eq("clicked")
  expect(will_click).to eq(true)
ensure
  button&.dispose
end

test(["Locator", "Locator.hover", "should work"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button onmouseenter="this.innerText = 'hovered';">test</button>
  HTML
  hovered = false
  page
    .locator("button")
    .on(Puppeteer::Bidi::LocatorEvent::ACTION) { hovered = true }
    .hover
  button = page.query_selector("button")
  text = button&.evaluate("el => el.innerText")
  expect(text).to eq("hovered")
  expect(hovered).to eq(true)
ensure
  button&.dispose
end

test(["Locator", "Locator.scroll", "should work"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <div style="height: 500px; width: 500px; overflow: scroll;">
      <div style="height: 1000px; width: 1000px;">test</div>
    </div>
  HTML
  scrolled = false
  page
    .locator("div")
    .on(Puppeteer::Bidi::LocatorEvent::ACTION) { scrolled = true }
    .scroll(scroll_top: 500, scroll_left: 500)
  scrollable = page.query_selector("div")
  scroll = scrollable&.evaluate("el => el.scrollTop + ' ' + el.scrollLeft")
  expect(scroll).to eq("500 500")
  expect(scrolled).to eq(true)
ensure
  scrollable&.dispose
end

test(["Locator", "Locator.fill", "should work for textarea"].join(" ")) do |page:|
  page.set_content("<textarea></textarea>")
  filled = false
  page
    .locator("textarea")
    .on(Puppeteer::Bidi::LocatorEvent::ACTION) { filled = true }
    .fill("test")
  expect(page.evaluate("() => document.querySelector('textarea')?.value === 'test'")).to eq(true)
  expect(filled).to eq(true)
end

test(["Locator", "Locator.fill", "should work for selects"].join(" ")) do |page:|
  page.set_content(<<~HTML)
    <select>
      <option value="value1">Option 1</option>
      <option value="value2">Option 2</option>
    </select>
  HTML
  filled = false
  page
    .locator("select")
    .on(Puppeteer::Bidi::LocatorEvent::ACTION) { filled = true }
    .fill("value2")
  expect(page.evaluate("() => document.querySelector('select')?.value === 'value2'")).to eq(true)
  expect(filled).to eq(true)
end

test(["Locator", "Locator.fill", "should work for inputs"].join(" ")) do |page:|
  page.set_content("<input />")
  page.locator("input").fill("test")
  expect(page.evaluate("() => document.querySelector('input')?.value === 'test'")).to eq(true)
end

test(["Locator", "Locator.fill", "should work for large text"].join(" ")) do |page:|
  page.set_content("<textarea></textarea>")
  text = "a" * 1000
  page.locator("textarea").fill(text)
  expect(page.evaluate("() => document.querySelector('textarea')?.value.length")).to eq(1000)
end

test(["Locator", "Locator.fill", "should work for large text in contenteditable"].join(" ")) do |page:|
  page.set_content('<div contenteditable="true"></div>')
  text = "a" * 1000
  page.locator("div").fill(text)
  expect(page.evaluate("() => document.querySelector('div')?.innerText.length")).to eq(1000)
end

test(["Locator", "Locator.fill", "should work with a custom typing threshold"].join(" ")) do |page:|
  page.set_content("<input />")
  page.locator("input").fill("abc", typing_threshold: 10)
  expect(page.evaluate("() => document.querySelector('input')?.value")).to eq("abc")

  page.set_content("<input />")
  page.locator("input").fill("abc", typing_threshold: 2)
  expect(page.evaluate("() => document.querySelector('input')?.value")).to eq("abc")
end

test(["Locator", "Locator.fill", "should work if the input becomes enabled later"].join(" ")) do |page:|
  page.set_content("<input disabled />")
  input = page.query_selector("input")
  raise "input not found" unless input

  fill_thread = Thread.new do
    page.locator("input").fill("test")
  end
  sleep 0.1
  expect(input.evaluate("el => el.value")).to eq("")
  input.evaluate("el => { el.disabled = false; }")
  fill_thread.value
  expect(input.evaluate("el => el.value")).to eq("test")
ensure
  input&.dispose
end

test(["Locator", "Locator.fill", "should work for contenteditable"].join(" ")) do |page:|
  page.set_content('<div contenteditable="true"></div>')
  page.locator("div").fill("test")
  expect(page.evaluate("() => document.querySelector('div')?.innerText === 'test'")).to eq(true)
end

test(["Locator", "Locator.fill", "should work for pre-filled inputs"].join(" ")) do |page:|
  page.set_content('<input value="te" />')
  page.locator("input").fill("test")
  expect(page.evaluate("() => document.querySelector('input')?.value === 'test'")).to eq(true)
end

test(["Locator", "Locator.fill", "should override pre-filled inputs"].join(" ")) do |page:|
  page.set_content('<input value="wrong prefix" />')
  page.locator("input").fill("test")
  expect(page.evaluate("() => document.querySelector('input')?.value === 'test'")).to eq(true)
end

test(["Locator", "Locator.fill", "should work for non-text inputs"].join(" ")) do |page:|
  page.set_content('<input type="color" />')
  page.locator("input").fill("#333333")
  expect(page.evaluate("() => document.querySelector('input')?.value === '#333333'")).to eq(true)
end

test(["Locator", "Locator.race", "races multiple locators"].join(" ")) do |page:|
  page.set_viewport(width: 500, height: 500)
  page.set_content(<<~HTML)
    <button onclick="window.count++;">test</button>
  HTML
  page.evaluate("() => { window.count = 0; }")
  Puppeteer::Bidi::Locator.race([
    page.locator("button"),
    page.locator("button"),
  ]).click
  count = page.evaluate("() => window.count")
  expect(count).to eq(1)
end

test(["Locator", "Locator.race", "can be aborted"].join(" ")) do
  skip "Abort signals are not implemented for locator actions in Ruby yet."
end

test(["Locator", "Locator.race", "should time out when all locators do not match"].join(" ")) do |page:|
  page.set_content("<button>test</button>")
  expect do
    Puppeteer::Bidi::Locator.race([
      page.locator("not-found"),
      page.locator("not-found"),
    ]).set_timeout(200).click
  end.to raise_error(Puppeteer::Bidi::TimeoutError, /Timed out after waiting 200ms/)
end

test(["Locator", "Locator.race", "should not time out when one of the locators matches"].join(" ")) do |page:|
  page.set_content("<button>test</button>")
  expect do
    Puppeteer::Bidi::Locator.race([
      page.locator("not-found"),
      page.locator("button"),
    ]).click
  end.not_to raise_error(StandardError)
end

test(["Locator", "Locator.prototype.map", "should work"].join(" ")) do |page:|
  page.set_content("<div>test</div>")
  expect(
    page
      .locator("::-p-text(test)")
      .map("(element) => element.getAttribute('clickable')")
      .wait
  ).to eq(nil)
  page.evaluate("() => document.querySelector('div')?.setAttribute('clickable', 'true')")
  expect(
    page
      .locator("::-p-text(test)")
      .map("(element) => element.getAttribute('clickable')")
      .wait
  ).to eq("true")
end

test(["Locator", "Locator.prototype.map", "should work with throws"].join(" ")) do |page:|
  page.set_content("<div>test</div>")
  result = Thread.new do
    page
      .locator("::-p-text(test)")
      .map(<<~JS)
        (element) => {
          const clickable = element.getAttribute("clickable");
          if (!clickable) {
            throw new Error("Missing `clickable` as an attribute");
          }
          return clickable;
        }
      JS
      .wait
  end
  sleep 0.1
  page.evaluate("() => document.querySelector('div')?.setAttribute('clickable', 'true')")
  expect(result.value).to eq("true")
end

test(["Locator", "Locator.prototype.map", "should work with expect"].join(" ")) do |page:|
  page.set_content("<div>test</div>")
  result = Thread.new do
    page
      .locator("::-p-text(test)")
      .filter("(element) => element.getAttribute('clickable') !== null")
      .map("(element) => element.getAttribute('clickable')")
      .wait
  end
  sleep 0.1
  page.evaluate("() => document.querySelector('div')?.setAttribute('clickable', 'true')")
  expect(result.value).to eq("true")
end

test(["Locator", "Locator.prototype.filter", "should resolve as soon as the predicate matches"].join(" ")) do |page:|
  page.set_content("<div>test</div>")
  result = Thread.new do
    page
      .locator("::-p-text(test)")
      .set_timeout(500)
      .filter("async (element) => element.getAttribute('clickable') === 'true'")
      .filter("(element) => element.getAttribute('clickable') === 'true'")
      .hover
  end
  sleep 0.2
  page.evaluate("() => document.querySelector('div')?.setAttribute('clickable', 'true')")
  expect(result.value).to eq(nil)
end

test(["Locator", "Locator.prototype.wait", "should work"].join(" ")) do |page:|
  page.set_content(<<~HTML)
    <script>
      setTimeout(() => {
        const element = document.createElement('div');
        element.innerText = 'test2';
        document.body.append(element);
      }, 50);
    </script>
  HTML
  page.locator("div").wait
end

test(["Locator", "Locator.prototype.wait_handle", "should work"].join(" ")) do |page:|
  page.set_content(<<~HTML)
    <script>
      setTimeout(() => {
        const element = document.createElement('div');
        element.innerText = 'test2';
        document.body.append(element);
      }, 50);
    </script>
  HTML
  handle = page.locator("div").wait_handle
  expect(handle).not_to be_nil
ensure
  handle&.dispose
end

test(["Locator", "Locator.prototype.clone", "should work"].join(" ")) do |page:|
  locator = page.locator("div")
  clone = locator.clone
  expect(locator).not_to eq(clone)
end

test(["Locator", "Locator.prototype.clone", "should work internally with delegated locators"].join(" ")) do |page:|
  locator = page.locator("div")
  delegated_locators = [
    locator.map("(div) => div.textContent"),
    locator.filter("(div) => (div.textContent || '').length === 0"),
  ]
  delegated_locators.each do |delegated|
    updated = delegated.set_timeout(500)
    expect(updated.timeout).not_to eq(locator.timeout)
  end
end

test(["Locator", "FunctionLocator", "should work"].join(" ")) do |page:|
  result = Thread.new do
    page
      .locator(function: <<~JS)
        () => {
          return new Promise(resolve => {
            return setTimeout(() => resolve(true), 100);
          });
        }
      JS
      .wait
  end
  expect(result.value).to eq(true)
end

test(["Locator", "FunctionLocator", "should work with actions"].join(" ")) do |page:|
  page.set_content('<div onclick="window.clicked = true">test</div>')
  page
    .locator(function: "() => document.getElementsByTagName('div')[0]")
    .click
  expect(page.evaluate("() => window.clicked")).to eq(true)
end
