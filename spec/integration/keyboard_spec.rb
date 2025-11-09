# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Keyboard' do
  describe 'Keyboard.type' do
    it 'should type into a textarea' do
      with_test_state do |page:, **|
        page.evaluate(<<~JS)
          () => {
            const textarea = document.createElement('textarea');
            document.body.appendChild(textarea);
            textarea.focus();
          }
        JS

        text = 'Hello world. I am the text that was typed!'
        page.keyboard.type(text)

        result = page.evaluate('() => document.querySelector("textarea").value')
        expect(result).to eq(text)
      end
    end

    it 'should move with the arrow keys' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        page.type('textarea', 'Hello World!')
        expect(page.evaluate('() => document.querySelector("textarea").value')).to eq('Hello World!')

        # Move left 6 times
        'World!'.length.times { page.keyboard.press('ArrowLeft') }
        page.keyboard.type('inserted ')
        expect(page.evaluate('() => document.querySelector("textarea").value')).to eq('Hello inserted World!')

        # Select text with shift+arrow (9 times, not 8)
        page.keyboard.down('Shift')
        'inserted '.length.times { page.keyboard.press('ArrowLeft') }
        page.keyboard.up('Shift')

        # Delete selected text
        page.keyboard.press('Backspace')
        expect(page.evaluate('() => document.querySelector("textarea").value')).to eq('Hello World!')
      end
    end

    it 'should trigger commands of keyboard shortcuts' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        page.type('textarea', 'hello')

        # Select all
        page.keyboard.down('CtrlOrMeta')
        page.keyboard.press('a')
        page.keyboard.up('CtrlOrMeta')

        # Copy
        page.keyboard.down('CtrlOrMeta')
        page.keyboard.down('c')
        page.keyboard.up('c')
        page.keyboard.up('CtrlOrMeta')

        # Paste twice
        page.keyboard.down('CtrlOrMeta')
        page.keyboard.press('v')
        page.keyboard.press('v')
        page.keyboard.up('CtrlOrMeta')

        result = page.evaluate('() => document.querySelector("textarea").value')
        expect(result).to eq('hellohello')
      end
    end

    it 'should trigger commands of keyboard shortcuts with commands option' do
      with_test_state do |page:, server:, **|
        cmd_key = RUBY_PLATFORM.include?('darwin') ? 'Meta' : 'Ctrl'

        page.goto("#{server.prefix}/input/textarea.html")
        page.type('textarea', 'hello')

        # Select all
        page.keyboard.down(cmd_key)
        page.keyboard.press('a', commands: ['SelectAll'])
        page.keyboard.up(cmd_key)

        # Copy
        page.keyboard.down(cmd_key)
        page.keyboard.down('c', commands: ['Copy'])
        page.keyboard.up('c')
        page.keyboard.up(cmd_key)

        # Paste twice
        page.keyboard.down(cmd_key)
        page.keyboard.press('v', commands: ['Paste'])
        page.keyboard.press('v', commands: ['Paste'])
        page.keyboard.up(cmd_key)

        result = page.evaluate('() => document.querySelector("textarea").value')
        expect(result).to eq('hellohello')
      end
    end

    it 'should send a character with ElementHandle.press' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        textarea = page.query_selector('textarea')

        textarea.press('a')
        expect(page.evaluate('() => document.querySelector("textarea").value')).to eq('a')

        # Prevent default on keydown
        page.evaluate(<<~JS)
          () => {
            window.addEventListener('keydown', event => event.preventDefault(), true);
          }
        JS

        textarea.press('b')
        # 'b' should not be added because keydown is prevented
        expect(page.evaluate('() => document.querySelector("textarea").value')).to eq('a')
      end
    end

    it 'ElementHandle.press should not support |text| option' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        textarea = page.query_selector('textarea')

        # Press 'a' with text option (should be ignored)
        textarea.press('a', text: 'ё')
        expect(page.evaluate('() => document.querySelector("textarea").value')).to eq('a')
      end
    end

    it 'should send a character with sendCharacter' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        page.focus('textarea')

        page.evaluate(<<~JS)
          () => {
            globalThis.inputCount = 0;
            globalThis.keyDownCount = 0;
            window.addEventListener(
              'input',
              () => {
                globalThis.inputCount += 1;
              },
              true
            );
            window.addEventListener(
              'keydown',
              () => {
                globalThis.keyDownCount += 1;
              },
              true
            );
          }
        JS

        page.keyboard.send_character('嗨')
        result = page.eval_on_selector('textarea', <<~JS)
          textarea => {
            return {
              value: textarea.value,
              inputs: globalThis.inputCount,
              keyDowns: globalThis.keyDownCount
            };
          }
        JS
        expect(result['value']).to eq('嗨')
        expect(result['inputs']).to eq(1)
        expect(result['keyDowns']).to eq(0)

        page.keyboard.send_character('a')
        result = page.eval_on_selector('textarea', <<~JS)
          textarea => {
            return {
              value: textarea.value,
              inputs: globalThis.inputCount,
              keyDowns: globalThis.keyDownCount
            };
          }
        JS
        expect(result['value']).to eq('嗨a')
        expect(result['inputs']).to eq(2)
        expect(result['keyDowns']).to eq(0)
      end
    end

    it 'should send a character with sendCharacter in iframe' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        # Attach iframe
        page.evaluate(<<~JS, server.prefix)
          async (src) => {
            const frame = document.createElement('iframe');
            frame.src = src + '/input/textarea.html';
            document.body.appendChild(frame);
            await new Promise(x => (frame.onload = x));
          }
        JS

        # Get iframe and focus textarea
        frames = page.evaluate(<<~JS)
          () => {
            const frame = document.querySelector('iframe');
            const textarea = frame.contentDocument.querySelector('textarea');
            textarea.focus();
            return true;
          }
        JS

        # Monitor events in iframe
        page.evaluate(<<~JS)
          () => {
            const frame = document.querySelector('iframe');
            const doc = frame.contentDocument;
            window.keydown_count = 0;
            window.input_count = 0;
            doc.querySelector('textarea').addEventListener('keydown', () => window.keydown_count++);
            doc.querySelector('textarea').addEventListener('input', () => window.input_count++);
          }
        JS

        page.keyboard.send_character('嗨')
        page.keyboard.send_character('a')

        result = page.evaluate(<<~JS)
          () => {
            const frame = document.querySelector('iframe');
            return frame.contentDocument.querySelector('textarea').value;
          }
        JS

        expect(result).to eq('嗨a')
        expect(page.evaluate('() => window.keydown_count')).to eq(0)
        expect(page.evaluate('() => window.input_count')).to eq(2)
      end
    end

    it 'should report shiftKey' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/keyboard.html")
        keyboard = page.keyboard
        code_for_key = ['Shift', 'Alt', 'Control']

        code_for_key.each do |modifier_key|
          keyboard.down(modifier_key)
          result = page.evaluate('() => globalThis.getResult()')
          expect(result).to eq("Keydown: #{modifier_key} #{modifier_key}Left [#{modifier_key}]")

          keyboard.down('!')
          result = page.evaluate('() => globalThis.getResult()')
          # Firefox BiDi: All modifiers may trigger input event with '!'
          # Just check that keydown includes the modifier
          expect(result).to include("Keydown: ! Digit1 [#{modifier_key}]")

          keyboard.up('!')
          result = page.evaluate('() => globalThis.getResult()')
          expect(result).to eq("Keyup: ! Digit1 [#{modifier_key}]")

          keyboard.up(modifier_key)
          result = page.evaluate('() => globalThis.getResult()')
          expect(result).to eq("Keyup: #{modifier_key} #{modifier_key}Left []")
        end
      end
    end

    it 'should report multiple modifiers' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/keyboard.html")
        keyboard = page.keyboard

        keyboard.down('Control')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq('Keydown: Control ControlLeft [Control]')

        keyboard.down('Alt')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq('Keydown: Alt AltLeft [Alt Control]')

        keyboard.down(';')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq('Keydown: ; Semicolon [Alt Control]')

        keyboard.up(';')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq('Keyup: ; Semicolon [Alt Control]')

        keyboard.up('Control')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq('Keyup: Control ControlLeft [Alt]')

        keyboard.up('Alt')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq('Keyup: Alt AltLeft []')
      end
    end

    it 'should send proper codes while typing' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/keyboard.html")

        page.keyboard.type('!')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq([
          'Keydown: ! Digit1 []',
          'input: ! insertText false',
          'Keyup: ! Digit1 []'
        ].join("\n"))

        page.keyboard.type('^')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq([
          'Keydown: ^ Digit6 []',
          'input: ^ insertText false',
          'Keyup: ^ Digit6 []'
        ].join("\n"))
      end
    end

    it 'should send proper codes while typing with shift' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/keyboard.html")

        keyboard = page.keyboard
        keyboard.down('Shift')
        page.keyboard.type('~')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq([
          'Keydown: Shift ShiftLeft [Shift]',
          'Keydown: ~ Backquote [Shift]',
          'input: ~ insertText false',
          'Keyup: ~ Backquote [Shift]'
        ].join("\n"))

        keyboard.up('Shift')
      end
    end

    it 'should not type canceled events' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        page.focus('textarea')

        page.evaluate(<<~JS)
          () => {
            window.addEventListener(
              'keydown',
              event => {
                event.stopPropagation();
                event.stopImmediatePropagation();
                if (event.key === 'l') {
                  event.preventDefault();
                }
                if (event.key === 'o') {
                  event.preventDefault();
                }
              },
              false
            );
          }
        JS

        page.keyboard.type('Hello World!')
        result = page.evaluate('() => globalThis.textarea.value')
        expect(result).to eq('He Wrd!')
      end
    end

    it 'should specify repeat property' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        page.focus('textarea')

        page.evaluate(<<~JS)
          () => {
            return document.querySelector('textarea').addEventListener(
              'keydown',
              e => {
                return (globalThis.lastEvent = e);
              },
              true
            );
          }
        JS

        page.keyboard.down('a')
        result = page.evaluate('() => globalThis.lastEvent.repeat')
        expect(result).to eq(false)

        page.keyboard.press('a')
        result = page.evaluate('() => globalThis.lastEvent.repeat')
        expect(result).to eq(true)

        page.keyboard.down('b')
        result = page.evaluate('() => globalThis.lastEvent.repeat')
        expect(result).to eq(false)

        page.keyboard.down('b')
        result = page.evaluate('() => globalThis.lastEvent.repeat')
        expect(result).to eq(true)

        page.keyboard.up('a')
        page.keyboard.down('a')
        result = page.evaluate('() => globalThis.lastEvent.repeat')
        expect(result).to eq(false)
      end
    end

    it 'should type all kinds of characters' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        page.focus('textarea')

        text = "This text goes onto two lines.\nThis character is 嗨."
        page.keyboard.type(text)
        result = page.evaluate('result')
        expect(result).to eq(text)
      end
    end

    it 'should specify location' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")

        page.evaluate(<<~JS)
          () => {
            window.addEventListener(
              'keydown',
              event => {
                return (globalThis.keyLocation = event.location);
              },
              true
            );
          }
        JS

        textarea = page.query_selector('textarea')

        textarea.press('Digit5')
        result = page.evaluate('keyLocation')
        expect(result).to eq(0)

        textarea.press('ControlLeft')
        result = page.evaluate('keyLocation')
        expect(result).to eq(1)

        textarea.press('ControlRight')
        result = page.evaluate('keyLocation')
        expect(result).to eq(2)

        textarea.press('NumpadSubtract')
        result = page.evaluate('keyLocation')
        expect(result).to eq(3)
      end
    end

    it 'should throw on unknown keys' do
      with_test_state do |page:, **|
        expect {
          page.keyboard.press('NotARealKey')
        }.to raise_error(/Unknown key: "NotARealKey"/)
      end
    end

    it 'should type emoji' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/input/textarea.html")
        page.type('textarea', '👹 Tokyo street Japan 🇯🇵')
        result = page.eval_on_selector('textarea', 'textarea => textarea.value')
        expect(result).to eq('👹 Tokyo street Japan 🇯🇵')
      end
    end

    it 'should type emoji into an iframe' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        # attachFrame helper equivalent
        page.evaluate(<<~JS, server.prefix)
          async (src) => {
            const frame = document.createElement('iframe');
            frame.name = 'emoji-test';
            frame.src = src + '/input/textarea.html';
            document.body.appendChild(frame);
            await new Promise(x => (frame.onload = x));
          }
        JS

        # Get frames - frames()[1] is the attached iframe
        frames = page.frames
        frame = frames[1]

        textarea = frame.query_selector('textarea')
        textarea.type('👹 Tokyo street Japan 🇯🇵')

        result = frame.eval_on_selector('textarea', 'textarea => textarea.value')
        expect(result).to eq('👹 Tokyo street Japan 🇯🇵')
      end
    end

    it 'should press the meta key', skip: !RUBY_PLATFORM.include?('darwin') do
      with_test_state do |page:, **|
        page.evaluate(<<~JS)
          () => {
            globalThis.result = null;
            document.addEventListener('keydown', event => {
              globalThis.result = [event.key, event.code, event.metaKey];
            });
          }
        JS

        page.keyboard.press('Meta')

        result = page.evaluate('result')
        key, code, meta_key = result

        expect(key).to eq('Meta')
        expect(code).to eq('MetaLeft')
        expect(meta_key).to eq(true)
      end
    end
  end
end
