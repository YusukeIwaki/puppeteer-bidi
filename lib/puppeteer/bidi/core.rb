# frozen_string_literal: true

# Core module provides low-level BiDi protocol abstractions
# This layer sits above the WebSocket transport and provides
# object-oriented semantics around WebDriver BiDi's flat API.
#
# Design principles:
# - Required arguments are method parameters, optional ones are keyword arguments
# - Session is never exposed on public methods except on Browser
# - Follows WebDriver BiDi spec strictly, not Puppeteer's needs
# - Implements BiDi comprehensively but minimally

require_relative 'core/errors'
require_relative 'core/event_emitter'
require_relative 'core/disposable'
require_relative 'core/session'
require_relative 'core/browser'
require_relative 'core/user_context'
require_relative 'core/browsing_context'
require_relative 'core/navigation'
require_relative 'core/realm'
require_relative 'core/request'
require_relative 'core/user_prompt'

module Puppeteer
  module Bidi
    # Core module containing low-level BiDi protocol classes
    module Core
      # This module provides:
      # - EventEmitter: Event subscription and emission
      # - Disposable: Resource management and cleanup
      # - Session: BiDi session management
      # - Browser: Browser instance management
      # - UserContext: Isolated browsing contexts (incognito-like)
      # - BrowsingContext: Individual tabs/windows/frames
      # - Navigation: Navigation tracking
      # - Realm: JavaScript execution contexts
      #   - WindowRealm: Window/iframe realms
      #   - DedicatedWorkerRealm: Dedicated worker realms
      #   - SharedWorkerRealm: Shared worker realms
      # - Request: Network request management
      # - UserPrompt: User prompt (alert/confirm/prompt) handling
    end
  end
end
