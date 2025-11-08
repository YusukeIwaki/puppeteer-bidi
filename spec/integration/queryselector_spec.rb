# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'QuerySelector', type: :integration do
  describe 'Page.query_selector' do
    it 'should query existing element' do
      with_test_state do |page:, server:, **|
        page.set_content('<section>test</section>')
        element = page.query_selector('section')
        expect(element).not_to be_nil
        expect(element).to be_a(Puppeteer::Bidi::ElementHandle)
      end
    end

    it 'should return null for non-existing element' do
      with_test_state do |page:, server:, **|
        page.set_content('<section>test</section>')
        element = page.query_selector('non-existing-element')
        expect(element).to be_nil
      end
    end
  end

  describe 'ElementHandle.query_selector' do
    it 'should query existing element' do
      with_test_state do |page:, server:, **|
        page.set_content('<div class="second"><div class="inner">A</div></div><div class="third"><div class="inner">B</div></div>')
        html = page.query_selector('html')
        expect(html).not_to be_nil

        second = html.query_selector('.second')
        expect(second).not_to be_nil

        inner = second.query_selector('.inner')
        expect(inner).not_to be_nil

        content = page.evaluate('(e) => e.textContent', inner)
        expect(content).to eq('A')
      end
    end

    it 'should return null for non-existing element' do
      with_test_state do |page:, server:, **|
        page.set_content('<div>test</div>')
        html = page.query_selector('html')
        element = html.query_selector('.non-existing')
        expect(element).to be_nil
      end
    end
  end

  describe 'Page.query_selector_all' do
    it 'should query existing elements' do
      with_test_state do |page:, server:, **|
        page.set_content('<div>A</div><br/><div>B</div>')
        elements = page.query_selector_all('div')
        expect(elements.length).to eq(2)

        # Verify we can evaluate on elements
        results = elements.map { |el| page.evaluate('(e) => e.textContent', el) }
        expect(results).to eq(['A', 'B'])
      end
    end

    it 'should return empty array for non-existing elements' do
      with_test_state do |page:, server:, **|
        page.set_content('<span>A</span>')
        elements = page.query_selector_all('div')
        expect(elements).to eq([])
      end
    end
  end

  describe 'ElementHandle.query_selector_all' do
    it 'should query existing elements' do
      with_test_state do |page:, server:, **|
        page.set_content('<div><p>A</p><p>B</p></div>')
        div = page.query_selector('div')
        elements = div.query_selector_all('p')
        expect(elements.length).to eq(2)

        results = elements.map { |el| page.evaluate('(e) => e.textContent', el) }
        expect(results).to eq(['A', 'B'])
      end
    end

    it 'should return empty array for non-existing elements' do
      with_test_state do |page:, server:, **|
        page.set_content('<div><span>A</span></div>')
        div = page.query_selector('div')
        elements = div.query_selector_all('p')
        expect(elements).to eq([])
      end
    end
  end

  describe 'Page.eval_on_selector' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.set_content('<section id="testAttribute">43543</section>')
        id_attribute = page.eval_on_selector('section', 'e => e.id')
        expect(id_attribute).to eq('testAttribute')
      end
    end

    it 'should accept arguments' do
      with_test_state do |page:, server:, **|
        page.set_content('<section>hello</section>')
        text = page.eval_on_selector('section', '(e, suffix) => e.textContent + suffix', ' world!')
        expect(text).to eq('hello world!')
      end
    end

    it 'should accept ElementHandles as arguments' do
      with_test_state do |page:, server:, **|
        page.set_content('<section>hello</section><div> world</div>')
        div_handle = page.query_selector('div')
        text = page.eval_on_selector('section', '(e, div) => e.textContent + div.textContent', div_handle)
        expect(text).to eq('hello world')
      end
    end

    it 'should throw error if no element is found' do
      with_test_state do |page:, server:, **|
        page.set_content('<section>test</section>')
        expect {
          page.eval_on_selector('non-existing-element', 'e => e.id')
        }.to raise_error(/failed to find element matching selector/)
      end
    end
  end

  describe 'ElementHandle.eval_on_selector' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.set_content('<html><body><div class="tweet"><div class="like">100</div><div class="retweets">10</div></div></body></html>')
        tweet = page.query_selector('.tweet')
        content = tweet.eval_on_selector('.like', 'node => node.innerText')
        expect(content).to eq('100')
      end
    end

    it 'should retrieve content from subtree' do
      with_test_state do |page:, server:, **|
        page.set_content('<div id="myId"><div class="a">a-child-div</div></div><div class="a">a-sibling-div</div>')
        element_handle = page.query_selector('#myId')
        content = element_handle.eval_on_selector('.a', 'node => node.innerText')
        expect(content).to eq('a-child-div')
      end
    end

    it 'should throw in case of missing selector' do
      with_test_state do |page:, server:, **|
        page.set_content('<div id="myId"></div>')
        element_handle = page.query_selector('#myId')
        expect {
          element_handle.eval_on_selector('.a', 'node => node.innerText')
        }.to raise_error('Error: failed to find element matching selector ".a"')
      end
    end
  end

  describe 'Page.eval_on_selector_all' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.set_content('<div>hello</div><div>beautiful</div><div>world!</div>')
        div_count = page.eval_on_selector_all('div', 'divs => divs.length')
        expect(div_count).to eq(3)
      end
    end

    it 'should accept extra arguments' do
      with_test_state do |page:, server:, **|
        page.set_content('<div>hello</div><div>beautiful</div><div>world!</div>')
        result = page.eval_on_selector_all('div', '(divs, two, three) => divs.length + two + three', 2, 3)
        expect(result).to eq(8)
      end
    end

    it 'should accept ElementHandles as arguments' do
      with_test_state do |page:, server:, **|
        page.set_content('<section>2</section><section>2</section><section>1</section><div>3</div>')
        div_handle = page.query_selector('div')
        result = page.eval_on_selector_all(
          'section',
          '(sections, div) => sections.reduce((acc, section) => acc + Number(section.textContent), 0) + Number(div.textContent)',
          div_handle
        )
        expect(result).to eq(8)
      end
    end

    it 'should handle many elements' do
      with_test_state do |page:, server:, **|
        # Create 1001 sections (0 to 1000)
        page.evaluate(<<~JS)
          (() => {
            for (let i = 0; i <= 1000; i++) {
              const section = document.createElement('section');
              section.textContent = i;
              document.body.appendChild(section);
            }
          })()
        JS

        sum = page.eval_on_selector_all(
          'section',
          'sections => sections.reduce((acc, section) => acc + Number(section.textContent), 0)'
        )
        expect(sum).to eq(500500)
      end
    end
  end

  describe 'ElementHandle.eval_on_selector_all' do
    it 'should retrieve content from subtree' do
      with_test_state do |page:, server:, **|
        page.set_content('<div class="myId"><div class="a">a1-child-div</div><div class="a">a2-child-div</div></div><div class="a">a-sibling-div</div>')
        element_handle = page.query_selector('.myId')
        result = element_handle.eval_on_selector_all('.a', 'nodes => nodes.map(n => n.innerText)')
        expect(result).to eq(['a1-child-div', 'a2-child-div'])
      end
    end

    it 'should not throw in case of missing selector' do
      with_test_state do |page:, server:, **|
        page.set_content('<div class="myId"></div>')
        element_handle = page.query_selector('.myId')
        result = element_handle.eval_on_selector_all('.a', 'nodes => nodes.length')
        expect(result).to eq(0)
      end
    end
  end
end
