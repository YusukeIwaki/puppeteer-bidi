# frozen_string_literal: true

require "test_helper"

    test(['input tests', 'ElementHandle.uploadFile', 'should upload the file'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/fileupload.html")
      input = page.query_selector('input')
      input.evaluate(<<~JS)
        (e) => {
          globalThis._inputEvents = [];
          e.addEventListener('change', (ev) => {
            return globalThis._inputEvents.push(ev.type);
          });
          e.addEventListener('input', (ev) => {
            return globalThis._inputEvents.push(ev.type);
          });
        }
      JS

      file_to_upload = asset_path("file-to-upload.txt")
      input.upload_file(file_to_upload)

      expect(input.evaluate('(e) => e.files?.[0]?.name')).to eq('file-to-upload.txt')
      expect(input.evaluate('(e) => e.files?.[0]?.type')).to eq('text/plain')
      expect(page.evaluate('() => globalThis._inputEvents')).to eq(%w[input change])
    end

    test(['input tests', 'ElementHandle.uploadFile', 'should read the file'].join(" ")) do |page:, server:|
      page.goto("#{server.prefix}/input/fileupload.html")
      input = page.query_selector('input')
      input.evaluate(<<~JS)
        (e) => {
          globalThis._inputEvents = [];
          e.addEventListener('change', (ev) => {
            return globalThis._inputEvents.push(ev.type);
          });
          e.addEventListener('input', (ev) => {
            return globalThis._inputEvents.push(ev.type);
          });
        }
      JS

      file_to_upload = asset_path("file-to-upload.txt")
      input.upload_file(file_to_upload)

      content = input.evaluate(<<~JS)
        (e) => {
          const file = e.files?.[0];
          if (!file) {
            throw new Error('No file found');
          }

          const reader = new FileReader();
          const promise = new Promise((fulfill) => {
            reader.addEventListener('load', fulfill);
          });
          reader.readAsText(file);

          return promise.then(() => {
            return reader.result;
          });
        }
      JS
      expect(content).to eq('contents of the file')
    end

    test(['input tests', 'Page.waitForFileChooser', 'should work when file input is attached to DOM'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" />')
      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      expect(chooser).to be_a(Puppeteer::Bidi::FileChooser)
    end

    test(['input tests', 'Page.waitForFileChooser', 'should work when file input is attached to DOM using JavaScript'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" />')
      chooser = page.wait_for_file_chooser do
        page.eval_on_selector('input', 'input => input.click()')
      end
      expect(chooser).to be_a(Puppeteer::Bidi::FileChooser)
    end

    test(['input tests', 'Page.waitForFileChooser', 'should work when file input is not attached to DOM'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      chooser = page.wait_for_file_chooser do
        page.evaluate(<<~JS)
          () => {
            const el = document.createElement('input');
            el.type = 'file';
            el.click();
          }
        JS
      end
      expect(chooser).not_to be_nil
    end

    test(['input tests', 'Page.waitForFileChooser', 'should respect timeout'].join(" ")) do |page:|
      expect {
        page.wait_for_file_chooser(timeout: 10) do
          # Do nothing - no file chooser triggered
        end
      }.to raise_error(Puppeteer::Bidi::TimeoutError)
    end

    test(['input tests', 'Page.waitForFileChooser', 'should respect default timeout when there is no custom timeout'].join(" ")) do |page:|
      page.default_timeout = 10
      expect {
        page.wait_for_file_chooser do
          # Do nothing - no file chooser triggered
        end
      }.to raise_error(Puppeteer::Bidi::TimeoutError)
    end

    test(['input tests', 'Page.waitForFileChooser', 'should prioritize exact timeout over default timeout'].join(" ")) do |page:|
      page.default_timeout = 0
      expect {
        page.wait_for_file_chooser(timeout: 10) do
          # Do nothing - no file chooser triggered
        end
      }.to raise_error(Puppeteer::Bidi::TimeoutError)
    end

    test(['input tests', 'Page.waitForFileChooser', 'should work with no timeout'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" />')
      chooser = page.wait_for_file_chooser(timeout: 0) do
        sleep 0.2
        page.click('input')
      end
      expect(chooser).to be_a(Puppeteer::Bidi::FileChooser)
    end

    test(['input tests', 'Page.waitForFileChooser', 'should return the same file chooser when there are many watchdogs simultaneously'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" />')

      # Note: In Ruby's block-based interface, we test that multiple
      # sequential calls work correctly
      chooser1 = Async { page.wait_for_file_chooser }
      chooser2 = page.wait_for_file_chooser do
        page.click('input')
      end

      expect(chooser1.wait).to be_a(Puppeteer::Bidi::FileChooser)
      expect(chooser2).to be_a(Puppeteer::Bidi::FileChooser)
    end

    test(['input tests', 'FileChooser.accept', 'should accept single file'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" oninput="javascript:console.timeStamp()" />')
      file_to_upload = asset_path("file-to-upload.txt")

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      chooser.accept([file_to_upload])

      expect(page.eval_on_selector('input', 'input => input.files.length')).to eq(1)
      expect(page.eval_on_selector('input', 'input => input.files[0].name')).to eq('file-to-upload.txt')
    end

    test(['input tests', 'FileChooser.accept', 'should be able to read selected file'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" />')
      file_to_upload = asset_path("file-to-upload.txt")

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      chooser.accept([file_to_upload])

      content = page.eval_on_selector('input', <<~JS)
        (pick) => {
          const reader = new FileReader();
          const promise = new Promise(fulfill => reader.onload = fulfill);
          reader.readAsText(pick.files[0]);
          return promise.then(() => reader.result);
        }
      JS
      expect(content).to eq('contents of the file')
    end

    test(['input tests', 'FileChooser.accept', 'should be able to reset selected files with empty file list'].join(" ")) do |page:|
      if linux?
        if headless_mode?
          skip 'Firefox crashes in headless mode on Linux'
        else
          pending 'Firefox BiDi does not trigger second file chooser in headful mode'
        end
      end

      page.set_content('<input type="file" />')
      file_to_upload = asset_path("file-to-upload.txt")

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      chooser.accept([file_to_upload])

      file_count = page.eval_on_selector('input', 'input => input.files.length')
      expect(file_count).to eq(1)

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      chooser.accept([])

      file_count = page.eval_on_selector('input', 'input => input.files.length')
      expect(file_count).to eq(0)
    end

    test(['input tests', 'FileChooser.accept', 'should not accept multiple files for single-file input'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" />')
      file_to_upload = asset_path("file-to-upload.txt")
      pptr_png = asset_path("pptr.png")

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end

      expect {
        chooser.accept([file_to_upload, pptr_png])
      }.to raise_error(RuntimeError)
    end

    test(['input tests', 'FileChooser.accept', 'should succeed even for non-existent files'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      # Firefox BiDi rejects non-existent files with NS_ERROR_FILE_NOT_FOUND
      pending 'Firefox BiDi rejects non-existent files'

      page.set_content('<input type="file" />')

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end

      expect {
        chooser.accept(['file-does-not-exist.txt'])
      }.not_to raise_error(StandardError)
    end

    test(['input tests', 'FileChooser.accept', 'should error on read of non-existent files'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      # Firefox BiDi rejects non-existent files with NS_ERROR_FILE_NOT_FOUND
      pending 'Firefox BiDi rejects non-existent files'

      page.set_content('<input type="file" />')

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      chooser.accept(['file-does-not-exist.txt'])

      result = page.eval_on_selector('input', <<~JS)
        (pick) => {
          const reader = new FileReader();
          const promise = new Promise(fulfill => reader.onerror = fulfill);
          reader.readAsText(pick.files[0]);
          return promise.then(() => false);
        }
      JS
      expect(result).to eq(false)
    end

    test(['input tests', 'FileChooser.accept', 'should fail when accepting file chooser twice'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" />')

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end

      chooser.accept([])
      expect {
        chooser.accept([])
      }.to raise_error(/Cannot accept FileChooser which is already handled!/)
    end

    test(['input tests', 'FileChooser.cancel', 'should cancel dialog'].join(" ")) do |page:|
      if linux?
        if headless_mode?
          skip 'Firefox crashes in headless mode on Linux'
        else
          pending 'Firefox BiDi does not trigger second file chooser in headful mode'
        end
      end

      # Consider file chooser canceled if we can summon another one.
      # There's no reliable way in WebPlatform to see that FileChooser was
      # canceled.
      page.set_content('<input type="file" />')

      chooser1 = page.wait_for_file_chooser do
        page.click('input')
      end
      chooser1.cancel

      # If this resolves, then we successfully canceled file chooser.
      chooser2 = page.wait_for_file_chooser do
        page.click('input')
      end
      expect(chooser2).not_to be_nil
    end

    test(['input tests', 'FileChooser.cancel', 'should fail when canceling file chooser twice'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" />')

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end

      chooser.cancel
      expect {
        chooser.cancel
      }.to raise_error(/Cannot cancel FileChooser which is already handled!/)
    end

    test(['input tests', 'FileChooser.isMultiple', 'should work for single file pick'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input type="file" />')

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end

      expect(chooser.multiple?).to eq(false)
    end

    test(['input tests', 'FileChooser.isMultiple', 'should work for "multiple"'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input multiple type="file" />')

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end

      expect(chooser.multiple?).to eq(true)
    end

    test(['input tests', 'FileChooser.isMultiple', 'should work for "webkitdirectory"'].join(" ")) do |page:|
      skip 'Firefox crashes in headless mode on Linux' if headless_mode? && linux?

      page.set_content('<input multiple webkitdirectory type="file" />')

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end

      expect(chooser.multiple?).to eq(true)
    end
