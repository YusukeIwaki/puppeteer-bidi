# frozen_string_literal: true

module Puppeteer
  module Bidi
    module Core
      # Base error class for Core module
      class Error < Puppeteer::Bidi::Error
      end

      # Raised when attempting to use a disposed resource
      class DisposedError < Error
        attr_reader :resource_type, :reason

        def initialize(resource_type, reason)
          @resource_type = resource_type
          @reason = reason
          super("#{resource_type} already disposed: #{reason}")
        end
      end

      # Raised when a realm has been destroyed
      class RealmDestroyedError < DisposedError
        def initialize(reason)
          super('Realm', reason)
        end
      end

      # Raised when a browsing context has been closed
      class BrowsingContextClosedError < DisposedError
        def initialize(reason)
          super('Browsing context', reason)
        end
      end

      # Raised when a user context has been closed
      class UserContextClosedError < DisposedError
        def initialize(reason)
          super('User context', reason)
        end
      end

      # Raised when a user prompt has been closed
      class UserPromptClosedError < DisposedError
        def initialize(reason)
          super('User prompt', reason)
        end
      end

      # Raised when a session has ended
      class SessionEndedError < DisposedError
        def initialize(reason)
          super('Session', reason)
        end
      end

      # Raised when a browser has been disconnected
      class BrowserDisconnectedError < DisposedError
        def initialize(reason)
          super('Browser', reason)
        end
      end
    end
  end
end
