# FileChooser Implementation

## Overview

FileChooser provides file upload functionality through the WebDriver BiDi `input.setFiles` command and `input.fileDialogOpened` event.

## Firefox Nightly Requirement

**Important**: The `input.fileDialogOpened` event is only supported in Firefox Nightly. Stable Firefox does not fire this event.

```bash
# Run tests with Firefox Nightly
FIREFOX_PATH="/Applications/Firefox Nightly.app/Contents/MacOS/firefox" bundle exec rspec spec/integration/input_spec.rb
```

The browser launcher prioritizes Firefox Nightly in its search order.

## API Design

### Block-based Interface

Ruby uses a block-based interface instead of JavaScript's Promise.all pattern:

```ruby
# Ruby (block-based)
chooser = page.wait_for_file_chooser do
  page.click('input[type=file]')
end
chooser.accept(['/path/to/file.txt'])

# JavaScript equivalent
const [chooser] = await Promise.all([
  page.waitForFileChooser(),
  page.click('input[type=file]'),
]);
await chooser.accept(['/path/to/file.txt']);
```

### Direct Upload

```ruby
input = page.query_selector('input[type=file]')
input.upload_file('/path/to/file.txt')
```

## Implementation Flow

```
ElementHandle#upload_file(files)
  └── Frame#set_files(element, files)
        └── BrowsingContext#set_files(shared_reference, files)
              └── BiDi command: input.setFiles
```

This follows Puppeteer's pattern where ElementHandle delegates to Frame, which then calls the BrowsingContext.

## Firefox BiDi Limitations

### 1. Detached Elements Not Supported

Firefox does not fire `input.fileDialogOpened` for file inputs that are not attached to the DOM:

```ruby
# This will timeout - detached element
page.wait_for_file_chooser do
  page.evaluate(<<~JS)
    () => {
      const el = document.createElement('input');
      el.type = 'file';
      el.click();  // No event fired
    }
  JS
end
```

### 2. Non-existent Files Rejected

Firefox BiDi rejects files that don't exist with `NS_ERROR_FILE_NOT_FOUND`. Chrome allows setting non-existent files.

### 3. Event Subscription

The `input` module must be subscribed at session level. This is handled automatically in `Session#initialize_session`:

```ruby
subscribe_modules = %w[browsingContext network log script input]
subscribe(subscribe_modules)
```

## Key Classes

- `FileChooser` - Wraps the element with `accept()`, `cancel()`, `multiple?()` methods
- `Page#wait_for_file_chooser` - Listens for `filedialogopened` event with timeout
- `ElementHandle#upload_file` - Resolves paths and delegates to frame
- `Frame#set_files` - Calls BrowsingContext with shared reference
- `BrowsingContext#set_files` - Sends BiDi `input.setFiles` command
