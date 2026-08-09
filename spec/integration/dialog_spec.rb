# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Page.Events.Dialog" do
  it "should fire" do
    with_test_state do |page:, **|
      dialogs = []
      page.on(:dialog) do |dialog|
        dialogs << dialog
        dialog.accept
      end

      page.evaluate("() => alert('yo')")

      expect(dialogs.length).to eq(1)
      dialog = dialogs.first
      expect(dialog.type).to eq("alert")
      expect(dialog.default_value).to eq("")
      expect(dialog.message).to eq("yo")
      expect(dialog.handled?).to be true
    end
  end

  it "should allow accepting prompts" do
    with_test_state do |page:, **|
      dialogs = []
      page.on(:dialog) do |dialog|
        dialogs << dialog
        dialog.accept("answer!")
      end

      result = page.evaluate("() => prompt('question?', 'yes.')")

      expect(dialogs.length).to eq(1)
      dialog = dialogs.first
      expect(dialog.type).to eq("prompt")
      expect(dialog.default_value).to eq("yes.")
      expect(dialog.message).to eq("question?")
      expect(dialog.handled?).to be true
      expect(result).to eq("answer!")
    end
  end

  it "should dismiss the prompt" do
    with_test_state do |page:, **|
      dialog = nil
      page.on(:dialog) do |opened_dialog|
        dialog = opened_dialog
        opened_dialog.dismiss
      end

      result = page.evaluate("() => prompt('question?')")

      expect(result).to be_nil
      expect(dialog.handled?).to be true
    end
  end

  it "should track dialogs handled outside the Dialog instance" do
    with_test_state do |page:, **|
      dialog_promise = Async::Promise.new
      page.once(:dialog) { |dialog| dialog_promise.resolve(dialog) }
      evaluation_task = Async do
        page.evaluate("() => prompt('question?', 'yes.')")
      end

      begin
        dialog = dialog_promise.wait
        expect(dialog.handled?).to be false

        page.main_frame.browsing_context.handle_user_prompt(accept: true, userText: "answer!").wait
        expect(evaluation_task.wait).to eq("answer!")

        # Wait for the userPromptClosed event to be processed by the Dialog instance.
        page.evaluate("() => 1")
        expect(dialog.handled?).to be true
      ensure
        evaluation_task&.stop
      end
    end
  end

  it "should see dialogs handled by other connections" do
    pending "Firefox does not support multiple active BiDi sessions"

    with_test_state do |page:, server:, browser:, **|
      page.goto(server.empty_page)
      browser2 = Puppeteer::Bidi.connect_to_browser_instance(browser.ws_endpoint)
      evaluation_task = nil

      begin
        page2 = browser2.pages.find { |candidate| candidate.url == server.empty_page }
        raise "Could not find page2" unless page2

        dialog1_promise = Async::Promise.new
        dialog2_promise = Async::Promise.new
        page.once(:dialog) { |dialog| dialog1_promise.resolve(dialog) }
        page2.once(:dialog) { |dialog| dialog2_promise.resolve(dialog) }

        evaluation_task = Async do
          page2.evaluate("() => prompt('question?', 'yes.')")
        end
        dialog1 = dialog1_promise.wait
        dialog2 = dialog2_promise.wait

        dialog2.accept("answer!")
        expect(evaluation_task.wait).to eq("answer!")
        page.evaluate("() => 1")

        expect(dialog1.handled?).to be true
        expect(dialog2.handled?).to be true
      ensure
        evaluation_task&.stop
        browser2&.disconnect
      end
    end
  end
end
