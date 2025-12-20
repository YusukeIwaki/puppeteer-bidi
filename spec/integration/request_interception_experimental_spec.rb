# frozen_string_literal: true

require "spec_helper"
require "async"
require "set"

RSpec.describe "Cooperative request interception" do
  def is_favicon?(request)
    request.url.end_with?("/favicon.ico")
  end

  def path_to_file_url(path)
    path_name = path.tr("\\", "/")
    path_name = "/#{path_name}" unless path_name.start_with?("/")
    "file://#{path_name}"
  end

  def wait_for_event(emitter, event, timeout: 5)
    promise = Async::Promise.new
    listener = proc do |data|
      promise.resolve(data) unless promise.resolved?
    end

    emitter.on(event, &listener)
    Puppeteer::Bidi::AsyncUtils.async_timeout(timeout * 1000, promise).wait
  ensure
    emitter.off(event, &listener)
  end

  describe "Page.set_request_interception" do
    %w[abort continue respond].each do |expected_action|
      it "should cooperatively #{expected_action} by priority" do
        with_test_state do |page:, server:, **|
          action_results = []
          page.set_request_interception(true)
          page.on(:request) do |request|
            if request.url.end_with?(".css")
              request.continue(
                { headers: request.headers.merge("xaction" => "continue") },
                expected_action == "continue" ? 1 : 0,
              )
            else
              request.continue({}, 0)
            end
          end
          page.on(:request) do |request|
            if request.url.end_with?(".css")
              request.respond(
                { headers: { "xaction" => "respond" } },
                expected_action == "respond" ? 1 : 0,
              )
            else
              request.continue({}, 0)
            end
          end
          page.on(:request) do |request|
            if request.url.end_with?(".css")
              request.abort("aborted", expected_action == "abort" ? 1 : 0)
            else
              request.continue({}, 0)
            end
          end
          page.on(:response) do |response|
            xaction = response.headers["xaction"]
            if response.url.end_with?(".css") && xaction
              action_results << xaction
            end
          end
          page.on(:requestfailed) do |request|
            action_results << "abort" if request.url.end_with?(".css")
          end

          response = if expected_action == "continue"
                       server_request = Async do
                         server.wait_for_request("/one-style.css")
                       end
                       response = page.goto("#{server.prefix}/one-style.html")
                       action_results << server_request.wait.headers["xaction"]
                       response
                     else
                       page.goto("#{server.prefix}/one-style.html")
                     end

          expect(action_results.length).to eq(1)
          expect(action_results[0]).to eq(expected_action)
          expect(response.ok?).to be(true)
        end
      end
    end

    it "should intercept" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        request_error = nil
        page.on(:request) do |request|
          if is_favicon?(request)
            request.continue({}, 0)
            next
          end
          begin
            expect(request).to be_truthy
            expect(request.url).to include("empty.html")
            expect(request.headers["user-agent"]).to be_truthy
            expect(request.method).to eq("GET")
            expect(request.navigation_request?).to be(true)
            expect(request.frame).to eq(page.main_frame)
            expect(request.frame.url).to eq("about:blank")
          rescue => error
            request_error = error
          ensure
            request.continue({}, 0)
          end
        end

        response = page.goto(server.empty_page)
        raise request_error if request_error

        expect(response.ok?).to be(true)
      end
    end

    it "should work when POST is redirected with 302" do
      with_test_state do |page:, server:, **|
        server.set_redirect("/rredirect", "/empty.html")
        page.goto(server.empty_page)
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({}, 0) }
        page.set_content(<<~HTML)
          <form action="/rredirect" method="post">
            <input type="hidden" id="foo" name="foo" value="FOOBAR">
          </form>
        HTML

        Puppeteer::Bidi::AsyncUtils.await_promise_all(
          -> { page.evaluate("() => document.querySelector('form').submit()") },
          -> { page.wait_for_navigation },
        )
      end
    end

    it "should work when header manipulation headers with redirect" do
      with_test_state do |page:, server:, **|
        server.set_redirect("/rrredirect", "/empty.html")
        page.set_request_interception(true)
        request_error = nil
        page.on(:request) do |request|
          headers = request.headers.merge("foo" => "bar")
          request.continue({ headers: headers }, 0)
          begin
            expect(request.continue_request_overrides).to eq(headers: headers)
          rescue => error
            request_error = error
          end
        end
        page.goto("#{server.prefix}/rrredirect")

        raise request_error if request_error
      end
    end

    it "should be able to remove headers" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          headers = request.headers.merge("foo" => "bar", "accept" => nil)
          request.continue({ headers: headers }, 0)
        end

        server_request = Async do
          server.wait_for_request("/empty.html")
        end
        page.goto("#{server.prefix}/empty.html")
        request = server_request.wait

        expect(request.headers["accept"]).to be_nil
      end
    end

    it "should contain referer header" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        requests = []
        page.on(:request) do |request|
          request.continue({}, 0)
          requests << request unless is_favicon?(request)
        end
        page.goto("#{server.prefix}/one-style.html")
        expect(requests[1].url).to include("/one-style.css")
        expect(requests[1].headers["referer"]).to include("/one-style.html")
      end
    end

    it "should properly return navigation response when URL has cookies" do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_cookie(name: "foo", value: "bar")

        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({}, 0) }
        response = page.reload

        expect(response.status).to eq(200)
      end
    end

    it "should stop intercepting" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.once(:request) { |request| request.continue({}, 0) }
        page.goto(server.empty_page)
        page.set_request_interception(false)
        page.goto(server.empty_page)
      end
    end

    it "should show custom HTTP headers" do
      with_test_state do |page:, server:, **|
        page.set_extra_http_headers("foo" => "bar")
        page.set_request_interception(true)
        request_error = nil
        page.on(:request) do |request|
          begin
            expect(request.headers["foo"]).to eq("bar")
          rescue => error
            request_error = error
          ensure
            request.continue({}, 0)
          end
        end
        response = page.goto(server.empty_page)
        raise request_error if request_error
        expect(response.ok?).to be(true)
      end
    end

    it "should work with redirect inside sync XHR" do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        server.set_redirect("/logo.png", "/pptr.png")
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({}, 0) }

        status = page.evaluate(<<~JS)
          () => {
            const request = new XMLHttpRequest();
            request.open('GET', '/logo.png', false);
            request.send(null);
            return request.status;
          }
        JS

        expect(status).to eq(200)
      end
    end

    it "should work with custom referer headers" do
      with_test_state do |page:, server:, **|
        page.set_extra_http_headers("referer" => server.empty_page)
        page.set_request_interception(true)
        request_error = nil
        page.on(:request) do |request|
          begin
            expect(request.headers["referer"]).to eq(server.empty_page)
          rescue => error
            request_error = error
          ensure
            request.continue({}, 0)
          end
        end
        response = page.goto(server.empty_page)
        raise request_error if request_error
        expect(response.ok?).to be(true)
      end
    end

    it "should be abortable" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          if request.url.end_with?(".css")
            request.abort("failed", 0)
          else
            request.continue({}, 0)
          end
        end
        failed_requests = 0
        page.on(:requestfailed) { failed_requests += 1 }

        response = page.goto("#{server.prefix}/one-style.html")
        expect(response.ok?).to be(true)
        expect(response.request.failure).to be_nil
        expect(failed_requests).to eq(1)
      end
    end

    it "should be able to access the error reason" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) { |request| request.abort("failed", 0) }

        abort_reason = nil
        page.on(:request) do |request|
          abort_reason = request.abort_error_reason
          request.continue({}, 0)
        end
        page.goto(server.empty_page) rescue nil
        expect(abort_reason).to eq("Failed")
      end
    end

    it "should be abortable with custom error codes" do
      pending "network.failRequest does not support error codes in BiDi"

      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) { |request| request.abort("internetdisconnected", 0) }

        failed_request = Async do
          wait_for_event(page, :requestfailed)
        end
        page.goto(server.empty_page) rescue nil

        request = failed_request.wait
        expect(request.failure["errorText"]).to include("net::ERR_INTERNET_DISCONNECTED")
      end
    end

    it "should send referer" do
      with_test_state do |page:, server:, **|
        page.set_extra_http_headers("referer" => "http://google.com/")
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({}, 0) }

        server_request = Async do
          server.wait_for_request("/grid.html")
        end
        page.goto("#{server.prefix}/grid.html")
        request = server_request.wait

        expect(request.headers["referer"]).to eq("http://google.com/")
      end
    end

    it "should fail navigation when aborting main resource" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) { |request| request.abort("failed", 0) }
        error = nil
        begin
          page.goto(server.empty_page)
        rescue => e
          error = e
        end
        expect(error).to be_truthy
      end
    end

    it "should work with redirects" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        requests = []
        page.on(:request) do |request|
          request.continue({}, 0)
          requests << request unless is_favicon?(request)
        end
        server.set_redirect("/non-existing-page.html", "/non-existing-page-2.html")
        server.set_redirect("/non-existing-page-2.html", "/non-existing-page-3.html")
        server.set_redirect("/non-existing-page-3.html", "/non-existing-page-4.html")
        server.set_redirect("/non-existing-page-4.html", "/empty.html")

        response = page.goto("#{server.prefix}/non-existing-page.html")
        expect(response.status).to eq(200)
        expect(response.url).to include("empty.html")
        expect(requests.length).to eq(5)

        redirect_chain = response.request.redirect_chain
        expect(redirect_chain.length).to eq(4)
        expect(redirect_chain[0].url).to include("/non-existing-page.html")
        expect(redirect_chain[2].url).to include("/non-existing-page-3.html")
        redirect_chain.each_with_index do |request, index|
          expect(request.navigation_request?).to be(true)
          expect(request.redirect_chain.index(request)).to eq(index)
        end
      end
    end

    it "should work with redirects for subresources" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        requests = []
        page.on(:request) do |request|
          request.continue({}, 0)
          requests << request unless is_favicon?(request)
        end
        server.set_redirect("/one-style.css", "/two-style.css")
        server.set_redirect("/two-style.css", "/three-style.css")
        server.set_redirect("/three-style.css", "/four-style.css")
        server.set_route("/four-style.css") do |_req, writer|
          writer.write("body {box-sizing: border-box; }")
          writer.finish
        end

        response = page.goto("#{server.prefix}/one-style.html")
        expect(response.status).to eq(200)
        expect(response.url).to include("one-style.html")
        expect(requests.length).to eq(5)

        redirect_chain = requests[1].redirect_chain
        expect(redirect_chain.length).to eq(3)
        expect(redirect_chain[0].url).to include("/one-style.css")
        expect(redirect_chain[2].url).to include("/three-style.css")
      end
    end

    it "should be able to abort redirects" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        server.set_redirect("/non-existing.json", "/non-existing-2.json")
        server.set_redirect("/non-existing-2.json", "/simple.html")
        page.on(:request) do |request|
          if request.url.include?("non-existing-2")
            request.abort("failed", 0)
          else
            request.continue({}, 0)
          end
        end
        page.goto(server.empty_page)

        result = page.evaluate(<<~JS)
          () => {
            return fetch('/non-existing.json').catch(error => error.message);
          }
        JS

        expect(result).to include("NetworkError").or include("Failed to fetch")
      end
    end

    it "should work with equal requests" do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        response_count = 1
        server.set_route("/zzz") do |_req, writer|
          writer.write((response_count * 11).to_s)
          writer.finish
          response_count += 1
        end
        page.set_request_interception(true)

        spinner = false
        page.on(:request) do |request|
          if is_favicon?(request)
            request.continue({}, 0)
            next
          end
          (spinner ? request.abort("failed", 0) : request.continue({}, 0))
          spinner = !spinner
        end

        results = page.evaluate(<<~JS)
          () => {
            return Promise.all([
              fetch('/zzz').then(response => response.text()).catch(() => 'FAILED'),
              fetch('/zzz').then(response => response.text()).catch(() => 'FAILED'),
              fetch('/zzz').then(response => response.text()).catch(() => 'FAILED'),
            ]);
          }
        JS

        expect(results).to eq(["11", "FAILED", "22"])
      end
    end

    it "should navigate to dataURL and fire dataURL requests" do
      with_test_state do |page:, **|
        page.set_request_interception(true)
        requests = []
        page.on(:request) do |request|
          requests << request unless is_favicon?(request)
          request.continue({}, 0)
        end
        data_url = "data:text/html,<div>yo</div>"
        response = page.goto(data_url)
        expect(response.status).to eq(200)
        expect(requests.length).to eq(1)
        expect(requests[0].url).to eq(data_url)
      end
    end

    it "should be able to fetch dataURL and fire dataURL requests" do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_request_interception(true)
        requests = []
        page.on(:request) do |request|
          request.continue({}, 0)
          requests << request unless is_favicon?(request)
        end
        data_url = "data:text/html,<div>yo</div>"
        text = page.evaluate("url => fetch(url).then(r => r.text())", data_url)
        expect(text).to eq("<div>yo</div>")
        expect(requests.length).to eq(1)
        expect(requests[0].url).to eq(data_url)
      end
    end

    it "should navigate to URL with hash and fire requests without hash" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        requests = []
        page.on(:request) do |request|
          requests << request unless is_favicon?(request)
          request.continue({}, 0)
        end
        response = page.goto("#{server.empty_page}#hash")
        expect(response.status).to eq(200)
        expect(response.url).to eq("#{server.empty_page}#hash")
        expect(requests.length).to eq(1)
        expect(requests[0].url).to eq("#{server.empty_page}#hash")
      end
    end

    it "should work with encoded server" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({}, 0) }
        response = page.goto("#{server.prefix}/some nonexisting page")
        expect(response.status).to eq(404)
      end
    end

    it "should work with badly encoded server" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        server.set_route("/malformed") { |_req, writer| writer.finish }
        page.on(:request) { |request| request.continue({}, 0) }
        response = page.goto("#{server.prefix}/malformed?rnd=%911")
        expect(response.status).to eq(200)
      end
    end

    it "should work with missing stylesheets" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        requests = []
        page.on(:request) do |request|
          request.continue({}, 0)
          requests << request unless is_favicon?(request)
        end
        response = page.goto("#{server.prefix}/style-404.html")
        expect(response.status).to eq(200)
        expect(requests.length).to eq(2)
        expect(requests[1].response.status).to eq(404)
      end
    end

    it "should not throw if the request was cancelled" do
      with_test_state do |page:, server:, **|
        page.set_content("<iframe></iframe>")
        page.set_request_interception(true)
        request_holder = nil
        page.on(:request) { |request| request_holder = request }

        Puppeteer::Bidi::AsyncUtils.await_promise_all(
          -> { page.evaluate("url => (document.querySelector('iframe').src = url)", server.empty_page) },
          -> { wait_for_event(page, :request) },
        )

        page.evaluate("() => document.querySelector('iframe').remove()")

        error = nil
        begin
          request_holder.continue({}, 0)
        rescue => e
          error = e
        end

        expect(error).to be_nil
      end
    end

    it "should throw if interception is not enabled" do
      with_test_state do |page:, server:, **|
        error = nil
        page.on(:request) do |request|
          begin
            request.continue({}, 0)
          rescue => e
            error = e
          end
        end
        page.goto(server.empty_page)
        expect(error.message).to include("Request Interception is not enabled")
      end
    end

    it "should work with file URLs" do
      with_test_state do |page:, **|
        page.set_request_interception(true)
        urls = Set.new
        page.on(:request) do |request|
          urls.add(request.url.split("/").last)
          request.continue({}, 0)
        end
        page.goto(
          path_to_file_url(
            File.join(__dir__, "../assets/one-style.html"),
          ),
        )
        expect(urls.size).to eq(2)
        expect(urls.include?("one-style.html")).to be(true)
        expect(urls.include?("one-style.css")).to be(true)
      end
    end

    [
      { url: "/cached/one-style.html", resource_type: "stylesheet" },
      { url: "/cached/one-script.html", resource_type: "script" },
    ].each do |case_data|
      it "should not cache #{case_data[:resource_type]} if cache disabled" do
        with_test_state do |page:, server:, **|
          page.goto("#{server.prefix}#{case_data[:url]}")

          page.set_request_interception(true)
          page.set_cache_enabled(false)
          page.on(:request) { |request| request.continue({}, 0) }

          cached = []
          page.on(:requestservedfromcache) { |request| cached << request }

          page.reload
          expect(cached.length).to eq(0)
        end
      end

      it "should cache #{case_data[:resource_type]} if cache enabled" do
        with_test_state do |page:, server:, **|
          page.goto("#{server.prefix}#{case_data[:url]}")

          page.set_request_interception(true)
          page.set_cache_enabled(true)
          page.on(:request) { |request| request.continue({}, 0) }

          cached = []
          page.on(:requestservedfromcache) { |request| cached << request }

          page.reload
          expect(cached.length).to eq(1)
        end
      end
    end

    it "should load fonts if cache enabled" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.set_cache_enabled(true)
        page.on(:request) { |request| request.continue({}, 0) }

        response_task = Async do
          page.wait_for_response(->(response) { response.url.end_with?("/one-style.woff") })
        end
        page.goto("#{server.prefix}/cached/one-style-font.html")
        response_task.wait
      end
    end
  end

  describe "Request.continue" do
    it "should work" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({}, 0) }
        page.goto(server.empty_page)
      end
    end

    it "should amend HTTP headers" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          headers = request.headers.merge("foo" => "bar")
          request.continue({ headers: headers }, 0)
        end
        page.goto(server.empty_page)

        server_request = Async do
          server.wait_for_request("/sleep.zzz")
        end
        page.evaluate("() => fetch('/sleep.zzz')")
        request = server_request.wait

        expect(request.headers["foo"]).to eq("bar")
      end
    end

    it "should redirect in a way non-observable to page" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          redirect_url = request.url.include?("/empty.html") ? "#{server.prefix}/consolelog.html" : nil
          request.continue({ url: redirect_url }, 0)
        end

        page.goto(server.empty_page)
        expect(page.url).to eq(server.empty_page)
        expect(page.title).to eq("console.log test")
      end
    end

    it "should amend method" do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({ method: "POST" }, 0) }

        server_request = Async do
          server.wait_for_request("/sleep.zzz")
        end
        page.evaluate("() => fetch('/sleep.zzz')")
        request = server_request.wait

        expect(request.method).to eq("POST")
      end
    end

    it "should amend post data" do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({ postData: "doggo" }, 0) }

        server_request = Async do
          server.wait_for_request("/sleep.zzz")
        end
        page.evaluate("() => fetch('/sleep.zzz', {method: 'POST', body: 'birdy'})")
        request = server_request.wait

        expect(request.post_body).to eq("doggo")
      end
    end

    it "should amend both post data and method on navigation" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({ method: "POST", postData: "doggo" }, 0) }

        server_request = Async do
          server.wait_for_request("/empty.html")
        end
        page.goto(server.empty_page)
        request = server_request.wait

        expect(request.method).to eq("POST")
        expect(request.post_body).to eq("doggo")
      end
    end
  end

  describe "Request.respond" do
    it "should work" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          request.respond(
            {
              status: 201,
              headers: {
                "foo" => "bar",
              },
              body: "Yo, page!",
            },
            0,
          )
        end
        response = page.goto(server.empty_page)
        expect(response.status).to eq(201)
        expect(response.headers["foo"]).to eq("bar")
        expect(page.evaluate("() => document.body.textContent")).to eq("Yo, page!")
      end
    end

    it "should be able to access the response" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          request.respond({ status: 200, body: "Yo, page!" }, 0)
        end
        response_override = nil
        page.on(:request) do |request|
          response_override = request.response_for_request
          request.continue({}, 0)
        end
        page.goto(server.empty_page)
        expect(response_override).to eq(status: 200, body: "Yo, page!")
      end
    end

    it "should work with status code 422" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          request.respond({ status: 422, body: "Yo, page!" }, 0)
        end
        response = page.goto(server.empty_page)
        expect(response.status).to eq(422)
        expect(response.status_text).to eq("Unprocessable Entity")
        expect(page.evaluate("() => document.body.textContent")).to eq("Yo, page!")
      end
    end

    it "should redirect" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          if request.url.include?("rrredirect")
            request.respond({ status: 302, headers: { "location" => server.empty_page } }, 0)
          else
            request.continue({}, 0)
          end
        end
        response = page.goto("#{server.prefix}/rrredirect")
        expect(response.request.redirect_chain.length).to eq(1)
        expect(response.request.redirect_chain[0].url).to eq("#{server.prefix}/rrredirect")
        expect(response.url).to eq(server.empty_page)
      end
    end

    it "should allow mocking binary responses" do
      pending "ElementHandle#screenshot is not implemented"

      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          image_buffer = File.binread(File.join(__dir__, "../assets/pptr.png"))
          request.respond({ contentType: "image/png", body: image_buffer }, 0)
        end

        page.evaluate(<<~JS, server.prefix)
          prefix => {
            const img = document.createElement('img');
            img.src = prefix + '/does-not-exist.png';
            document.body.appendChild(img);
            return new Promise(resolve => (img.onload = resolve));
          }
        JS

        img = page.query_selector("img")
        screenshot = img.screenshot
        expect(compare_with_golden(screenshot, "mock-binary-response.png")).to be(true)
      end
    end

    it "should stringify intercepted request response headers" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) do |request|
          request.respond({ status: 200, headers: { "foo" => true }, body: "Yo, page!" }, 0)
        end
        response = page.goto(server.empty_page)
        expect(response.status).to eq(200)
        expect(response.headers["foo"]).to eq("true")
        expect(page.evaluate("() => document.body.textContent")).to eq("Yo, page!")
      end
    end

    it "should indicate already-handled if an intercept has been handled" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue }
        request_error = nil
        page.on(:request) do |request|
          begin
            expect(request.intercept_resolution_handled?).to be(true)
          rescue => error
            request_error = error
          end
        end
        page.on(:request) do |request|
          action = request.intercept_resolution_state[:action]
          begin
            expect(action).to eq(Puppeteer::Bidi::HTTPRequest::InterceptResolutionAction::ALREADY_HANDLED)
          rescue => error
            request_error = error
          end
        end
        page.goto(server.empty_page)
        raise request_error if request_error
      end
    end
  end

  describe "Request.resource_type" do
    it "should work for document type" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        page.on(:request) { |request| request.continue({}, 0) }
        response = page.goto(server.empty_page)
        request = response.request
        expect(request.resource_type).to eq("document")
      end
    end

    it "should work for stylesheets" do
      with_test_state do |page:, server:, **|
        page.set_request_interception(true)
        css_requests = []
        page.on(:request) do |request|
          css_requests << request if request.url.end_with?("css")
          request.continue({}, 0)
        end
        page.goto("#{server.prefix}/one-style.html")
        expect(css_requests.length).to eq(1)
        request = css_requests[0]
        expect(request.url).to include("one-style.css")
        expect(request.resource_type).to eq("stylesheet")
      end
    end
  end
end
