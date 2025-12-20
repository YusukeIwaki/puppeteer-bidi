# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'input tests' do
  describe 'ElementHandle.uploadFile' do
    it 'should upload the file' do
      with_test_state do |page:, server:, **|
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

        file_to_upload = File.expand_path('../assets/file-to-upload.txt', __dir__)
        input.upload_file(file_to_upload)

        expect(input.evaluate('(e) => e.files?.[0]?.name')).to eq('file-to-upload.txt')
        expect(input.evaluate('(e) => e.files?.[0]?.type')).to eq('text/plain')
        expect(page.evaluate('() => globalThis._inputEvents')).to eq(%w[input change])
      end
    end

    it 'should read the file' do
      with_test_state do |page:, server:, **|
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

        file_to_upload = File.expand_path('../assets/file-to-upload.txt', __dir__)
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
    end
  end

  describe 'Page.waitForFileChooser' do
    it 'should work when file input is attached to DOM' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" />')
        chooser = page.wait_for_file_chooser do
          page.click('input')
        end
        expect(chooser).to be_a(Puppeteer::Bidi::FileChooser)
      end
    end

    it 'should work when file input is attached to DOM using JavaScript' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" />')
        chooser = page.wait_for_file_chooser do
          page.eval_on_selector('input', 'input => input.click()')
        end
        expect(chooser).to be_a(Puppeteer::Bidi::FileChooser)
      end
    end

    it 'should work when file input is not attached to DOM' do
      with_test_state do |page:, **|
        chooser = page.wait_for_file_chooser do
          page.evaluate(<<~JS)
            () => {
              const el = document.createElement('input');
              el.type = 'file';
              el.click();
            }
          JS
        end
        expect(chooser).to be_truthy
      end
    end

    it 'should respect timeout' do
      with_test_state do |page:, **|
        expect {
          page.wait_for_file_chooser(timeout: 10) do
            # Do nothing - no file chooser triggered
          end
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end

    it 'should respect default timeout when there is no custom timeout' do
      with_test_state do |page:, **|
        page.default_timeout = 10
        expect {
          page.wait_for_file_chooser do
            # Do nothing - no file chooser triggered
          end
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end

    it 'should prioritize exact timeout over default timeout' do
      with_test_state do |page:, **|
        page.default_timeout = 0
        expect {
          page.wait_for_file_chooser(timeout: 10) do
            # Do nothing - no file chooser triggered
          end
        }.to raise_error(Puppeteer::Bidi::TimeoutError)
      end
    end

    it 'should work with no timeout' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" />')
        chooser = page.wait_for_file_chooser(timeout: 0) do
          sleep 0.2
          page.click('input')
        end
        expect(chooser).to be_a(Puppeteer::Bidi::FileChooser)
      end
    end

    it 'should return the same file chooser when there are many watchdogs simultaneously' do
      with_test_state do |page:, **|
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
    end
  end

  describe 'FileChooser.accept' do
    it 'should accept single file' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" oninput="javascript:console.timeStamp()" />')
        file_to_upload = File.expand_path('../assets/file-to-upload.txt', __dir__)

        chooser = page.wait_for_file_chooser do
          page.click('input')
        end
        chooser.accept([file_to_upload])

        expect(page.eval_on_selector('input', 'input => input.files.length')).to eq(1)
        expect(page.eval_on_selector('input', 'input => input.files[0].name')).to eq('file-to-upload.txt')
      end
    end

    it 'should be able to read selected file' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" />')
        file_to_upload = File.expand_path('../assets/file-to-upload.txt', __dir__)

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
    end

    it 'should be able to reset selected files with empty file list' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" />')
        file_to_upload = File.expand_path('../assets/file-to-upload.txt', __dir__)

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
    end

    it 'should not accept multiple files for single-file input' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" />')
        file_to_upload = File.expand_path('../assets/file-to-upload.txt', __dir__)
        pptr_png = File.expand_path('../assets/pptr.png', __dir__)

        chooser = page.wait_for_file_chooser do
          page.click('input')
        end

        expect {
          chooser.accept([file_to_upload, pptr_png])
        }.to raise_error(RuntimeError)
      end
    end

    it 'should succeed even for non-existent files' do
      # Firefox BiDi rejects non-existent files with NS_ERROR_FILE_NOT_FOUND
      pending 'Firefox BiDi rejects non-existent files'

      with_test_state do |page:, **|
        page.set_content('<input type="file" />')

        chooser = page.wait_for_file_chooser do
          page.click('input')
        end

        expect {
          chooser.accept(['file-does-not-exist.txt'])
        }.not_to raise_error
      end
    end

    it 'should error on read of non-existent files' do
      # Firefox BiDi rejects non-existent files with NS_ERROR_FILE_NOT_FOUND
      pending 'Firefox BiDi rejects non-existent files'

      with_test_state do |page:, **|
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
        expect(result).to be_falsy
      end
    end

    it 'should fail when accepting file chooser twice' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" />')

        chooser = page.wait_for_file_chooser do
          page.click('input')
        end

        chooser.accept([])
        expect {
          chooser.accept([])
        }.to raise_error(/Cannot accept FileChooser which is already handled!/)
      end
    end
  end

  describe 'FileChooser.cancel' do
    it 'should cancel dialog' do
      with_test_state do |page:, **|
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
        expect(chooser2).to be_truthy
      end
    end

    it 'should fail when canceling file chooser twice' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" />')

        chooser = page.wait_for_file_chooser do
          page.click('input')
        end

        chooser.cancel
        expect {
          chooser.cancel
        }.to raise_error(/Cannot cancel FileChooser which is already handled!/)
      end
    end
  end

  describe 'FileChooser.isMultiple' do
    it 'should work for single file pick' do
      with_test_state do |page:, **|
        page.set_content('<input type="file" />')

        chooser = page.wait_for_file_chooser do
          page.click('input')
        end

        expect(chooser.multiple?).to be false
      end
    end

    it 'should work for "multiple"' do
      with_test_state do |page:, **|
        page.set_content('<input multiple type="file" />')

        chooser = page.wait_for_file_chooser do
          page.click('input')
        end

        expect(chooser.multiple?).to be true
      end
    end

    it 'should work for "webkitdirectory"' do
      with_test_state do |page:, **|
        page.set_content('<input multiple webkitdirectory type="file" />')

        chooser = page.wait_for_file_chooser do
          page.click('input')
        end

        expect(chooser.multiple?).to be true
      end
    end
  end
end
