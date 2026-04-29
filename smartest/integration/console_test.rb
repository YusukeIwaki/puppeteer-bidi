# frozen_string_literal: true

require "test_helper"

# rubocop:disable Metrics/BlockLength
  def wait_for_console_message(page, timeout: 2)
    message = nil
    page.once(:console) { |msg| message = msg }
    yield
    deadline = Time.now + timeout
    sleep 0.05 until message || Time.now > deadline
    message
  end

  def wait_for_console_messages(page, count:, timeout: 2)
    messages = []
    page.on(:console) { |msg| messages << msg }
    yield
    deadline = Time.now + timeout
    sleep 0.05 until messages.length >= count || Time.now > deadline
    messages
  end

  test(["console", "should work"].join(" ")) do |page:|
    message = wait_for_console_message(page) do
      page.evaluate("() => console.log('hello', 5, {foo: 'bar'})")
    end

    expect(message).not_to be_nil
    expect([
             "hello 5 [object Object]",
             "hello 5 JSHandle@object"
           ]).to include(message.text)
    expect(message.type).to eq("log")
    expect(message.args.length).to eq(3)
    expect(message.args[0].json_value).to eq("hello")
    expect(message.args[1].json_value).to eq(5)
    expect(message.args[2].json_value).to eq({ "foo" => "bar" })
  end

  test(["console", "should work for Error instances"].join(" ")) do |page:|
    pending "Firefox BiDi log entries do not include Error message details for console args"

    message = wait_for_console_message(page) do
      page.evaluate("() => console.log(new Error('test error'))")
    end

    expect(message.text).to eq("Error: test error")
    expect(message.type).to eq("log")
    expect(message.args.length).to eq(1)
  end

  test(["console", "should return the first line of the error message in text"].join(" ")) do |page:|
    pending "Firefox BiDi log entries do not include Error message details for console args"

    message = wait_for_console_message(page) do
      page.evaluate("() => console.log(new Error('test error\\nsecond line'))")
    end

    expect(message.text).to eq("Error: test error")
    expect(message.type).to eq("log")
    expect(message.args.length).to eq(1)
  end

  test(["console", "should work on script call right after navigation"].join(" ")) do |page:|
    message = wait_for_console_message(page) do
      page.goto("data:text/html,<!DOCTYPE html><script>console.log('SOME_LOG_MESSAGE');</script>")
    end

    expect(message.text).to eq("SOME_LOG_MESSAGE")
  end

  test(["console", "should work for different console API calls with logging functions"].join(" ")) do |page:|
    messages = wait_for_console_messages(page, count: 5) do
      page.evaluate(<<~JS)
        () => {
          console.trace('calling console.trace');
          console.dir('calling console.dir');
          console.warn('calling console.warn');
          console.error('calling console.error');
          console.log(Promise.resolve('should not wait until resolved!'));
        }
      JS
    end

    expect(messages.map(&:type)).to eq(%w[trace dir warn error log])
    expect(messages.map(&:text)).to eq([
                                         "calling console.trace",
                                         "calling console.dir",
                                         "calling console.warn",
                                         "calling console.error",
                                         "JSHandle@promise"
                                       ])
  end

  test(["console", "should work for different console API calls with timing functions"].join(" ")) do |page:|
    messages = wait_for_console_messages(page, count: 1) do
      page.evaluate(<<~JS)
        () => {
          console.time('calling console.time');
          console.timeEnd('calling console.time');
        }
      JS
    end

    expect(messages.map(&:type)).to eq(%w[timeEnd])
    expect(messages.first.text).to include("calling console.time")
  end

  test(["console", "should work for different console API calls with group functions"].join(" ")) do |page:|
    messages = wait_for_console_messages(page, count: 2) do
      page.evaluate(<<~JS)
        () => {
          console.group('calling console.group');
          console.groupEnd();
        }
      JS
    end

    pending "console.groupEnd is not emitted by this browser" if messages.map(&:type) == %w[startGroup]
    expect(messages.map(&:type)).to eq(%w[startGroup endGroup])
    expect(messages.first.text).to include("calling console.group")
  end

  test(["console", "should not fail for window object"].join(" ")) do |page:|
    message = wait_for_console_message(page) do
      page.evaluate("() => console.error(window)")
    end

    expect([
             "[object Object]",
             "[object Window]",
             "JSHandle@window"
           ]).to include(message.text)
  end

  test(["console", "should return remote objects"].join(" ")) do |page:|
    pending "Firefox BiDi log args for Window do not include handles that can read properties"

    message = wait_for_console_message(page) do
      page.evaluate(<<~JS)
        () => {
          globalThis.test = 1;
          console.log(1, 2, 3, globalThis);
        }
      JS
    end

    expect([
             "1 2 3 [object Object]",
             "1 2 3 [object Window]",
             "1 2 3 JSHandle@object",
             "1 2 3 JSHandle@window"
           ]).to include(message.text)
    expect(message.args.length).to eq(4)
    property = message.args[3].get_property("test")
    expect(property.json_value).to eq(1)
  end

  test(["console", "should trigger correct Log"].join(" ")) do |page:, server:|
    pending "Firefox BiDi does not emit this CORS failure as a console event consistently"

    page.goto("about:blank")

    message = wait_for_console_message(page) do
      page.evaluate("async url => fetch(url).catch(e => {})", "#{server.cross_process_prefix}/non-existent")
    end

    expect(message).not_to be_nil
    expect(message.text).to include("Access-Control-Allow-Origin")
    expect(%w[error warn]).to include(message.type)
  end

  test(["console", "should have location when fetch fails"].join(" ")) do |page:, server:|
    pending "Firefox BiDi does not emit this network failure as a console event consistently"

    page.goto(server.empty_page)

    message = wait_for_console_message(page) do
      page.set_content("<script>fetch('http://wat');</script>")
    end

    expect(message).not_to be_nil
    expect(message.text).to include("ERR_NAME_NOT_RESOLVED")
    expect(message.type).to eq("error")
    expect(message.location).to eq({
                                     url: "http://wat/",
                                     line_number: nil
                                   })
  end

  test(["console", "should have location and stack trace for console API calls"].join(" ")) do |page:, server:|
    page.goto(server.empty_page)

    message = wait_for_console_message(page) do
      page.goto("#{server.prefix}/consoletrace.html")
    end

    expect(message).not_to be_nil
    expect(message.text).to eq("yellow")
    expect(message.type).to eq("trace")
    expect(message.location).to eq({
                                     url: "#{server.prefix}/consoletrace.html",
                                     line_number: 8,
                                     column_number: 16
                                   })
    expect(message.stack_trace.first).to eq({
                                              url: "#{server.prefix}/consoletrace.html",
                                              line_number: 8,
                                              column_number: 16,
                                              function_name: "foo"
                                            })
  end
# rubocop:enable Metrics/BlockLength
