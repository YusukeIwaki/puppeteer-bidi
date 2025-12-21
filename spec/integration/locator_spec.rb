# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Locator" do
  def wait_for_frame(page, timeout: 2)
    deadline = Time.now + timeout
    loop do
      frame = page.frames.find { |candidate| yield candidate }
      return frame if frame
      raise "Frame not found" if Time.now > deadline
      sleep 0.05
    end
  end

  it "should work with a frame" do
    with_test_state do |page:, **|
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
  end

  it "should work without preconditions" do
    with_test_state do |page:, **|
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
  end

  describe "Locator.click" do
    it "should work" do
      with_test_state do |page:, **|
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
    end

    it "should work for multiple selectors" do
      with_test_state do |page:, **|
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
    end

    it "should work if the element is out of viewport" do
      with_test_state do |page:, **|
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
    end

    it "should work with element handles" do
      with_test_state do |page:, **|
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
    end

    it "should work if the element becomes visible later" do
      with_test_state do |page:, **|
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
    end

    it "should work if the element becomes enabled later" do
      with_test_state do |page:, **|
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
    end

    it "should work if multiple conditions are satisfied later" do
      with_test_state do |page:, **|
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
    end

    it "should time out" do
      with_test_state do |page:, **|
        page.set_default_timeout(200)
        page.set_viewport(width: 500, height: 500)
        page.set_content(<<~HTML)
          <button style="display: none;" onclick="this.innerText = 'clicked';">
            test
          </button>
        HTML
        expect do
          page.locator("button").click
        end.to raise_error(Puppeteer::Bidi::TimeoutError, "Timed out after waiting 200ms")
      end
    end

    it "should work with an iframe" do
      with_test_state do |page:, **|
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
    end
  end

  describe "Locator.hover" do
    it "should work" do
      with_test_state do |page:, **|
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
    end
  end

  describe "Locator.scroll" do
    it "should work" do
      with_test_state do |page:, **|
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
    end
  end

  describe "Locator.fill" do
    it "should work for textarea" do
      with_test_state do |page:, **|
        page.set_content("<textarea></textarea>")
        filled = false
        page
          .locator("textarea")
          .on(Puppeteer::Bidi::LocatorEvent::ACTION) { filled = true }
          .fill("test")
        expect(page.evaluate("() => document.querySelector('textarea')?.value === 'test'")).to eq(true)
        expect(filled).to eq(true)
      end
    end

    it "should work for selects" do
      with_test_state do |page:, **|
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
    end

    it "should work for inputs" do
      with_test_state do |page:, **|
        page.set_content("<input />")
        page.locator("input").fill("test")
        expect(page.evaluate("() => document.querySelector('input')?.value === 'test'")).to eq(true)
      end
    end

    it "should work if the input becomes enabled later" do
      with_test_state do |page:, **|
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
    end

    it "should work for contenteditable" do
      with_test_state do |page:, **|
        page.set_content('<div contenteditable="true"></div>')
        page.locator("div").fill("test")
        expect(page.evaluate("() => document.querySelector('div')?.innerText === 'test'")).to eq(true)
      end
    end

    it "should work for pre-filled inputs" do
      with_test_state do |page:, **|
        page.set_content('<input value="te" />')
        page.locator("input").fill("test")
        expect(page.evaluate("() => document.querySelector('input')?.value === 'test'")).to eq(true)
      end
    end

    it "should override pre-filled inputs" do
      with_test_state do |page:, **|
        page.set_content('<input value="wrong prefix" />')
        page.locator("input").fill("test")
        expect(page.evaluate("() => document.querySelector('input')?.value === 'test'")).to eq(true)
      end
    end

    it "should work for non-text inputs" do
      with_test_state do |page:, **|
        page.set_content('<input type="color" />')
        page.locator("input").fill("#333333")
        expect(page.evaluate("() => document.querySelector('input')?.value === '#333333'")).to eq(true)
      end
    end
  end

  describe "Locator.race" do
    it "races multiple locators" do
      with_test_state do |page:, **|
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
    end

    it "should time out when all locators do not match" do
      with_test_state do |page:, **|
        page.set_content("<button>test</button>")
        expect do
          Puppeteer::Bidi::Locator.race([
            page.locator("not-found"),
            page.locator("not-found"),
          ]).set_timeout(200).click
        end.to raise_error(Puppeteer::Bidi::TimeoutError, "Timed out after waiting 200ms")
      end
    end

    it "should not time out when one of the locators matches" do
      with_test_state do |page:, **|
        page.set_content("<button>test</button>")
        expect do
          Puppeteer::Bidi::Locator.race([
            page.locator("not-found"),
            page.locator("button"),
          ]).click
        end.not_to raise_error
      end
    end
  end

  describe "Locator.prototype.map" do
    it "should work" do
      with_test_state do |page:, **|
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
    end

    it "should work with throws" do
      with_test_state do |page:, **|
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
    end

    it "should work with expect" do
      with_test_state do |page:, **|
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
    end
  end

  describe "Locator.prototype.filter" do
    it "should resolve as soon as the predicate matches" do
      with_test_state do |page:, **|
        page.set_content("<div>test</div>")
        result = Thread.new do
          page
            .locator("::-p-text(test)")
            .set_timeout(500)
            .filter("(element) => element.getAttribute('clickable') === 'true'")
            .filter("(element) => element.getAttribute('clickable') === 'true'")
            .hover
        end
        sleep 0.2
        page.evaluate("() => document.querySelector('div')?.setAttribute('clickable', 'true')")
        expect(result.value).to eq(nil)
      end
    end
  end

  describe "Locator.prototype.wait" do
    it "should work" do
      with_test_state do |page:, **|
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
    end
  end

  describe "Locator.prototype.wait_handle" do
    it "should work" do
      with_test_state do |page:, **|
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
    end
  end

  describe "Locator.prototype.clone" do
    it "should work" do
      with_test_state do |page:, **|
        locator = page.locator("div")
        clone = locator.clone
        expect(locator).not_to eq(clone)
      end
    end

    it "should work internally with delegated locators" do
      with_test_state do |page:, **|
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
    end
  end

  describe "FunctionLocator" do
    it "should work" do
      with_test_state do |page:, **|
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
    end

    it "should work with actions" do
      with_test_state do |page:, **|
        page.set_content('<div onclick="window.clicked = true">test</div>')
        page
          .locator(function: "() => document.getElementsByTagName('div')[0]")
          .click
        expect(page.evaluate("() => window.clicked")).to eq(true)
      end
    end
  end
end
