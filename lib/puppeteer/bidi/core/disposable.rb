# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    module Core
      # Disposable provides resource management and cleanup capabilities
      # Similar to TypeScript's DisposableStack
      module Disposable
        # DisposableStack manages multiple disposable resources
        class DisposableStack
          # @rbs return: void
          def initialize
            @disposed = false
            @resources = [] #: Array[untyped]
          end

          # Add a disposable resource to the stack
          # @rbs resource: untyped
          # @rbs return: untyped
          def use(resource)
            raise 'DisposableStack already disposed' if @disposed
            @resources << resource
            resource
          end

          # Dispose all resources in reverse order (LIFO)
          # @rbs return: void
          def dispose
            return if @disposed
            @disposed = true

            # Dispose in reverse order
            @resources.reverse_each do |resource|
              begin
                resource.dispose if resource.respond_to?(:dispose)
              rescue => e
                warn "Error disposing resource: #{e.message}"
              end
            end

            @resources.clear
          end

          # @rbs return: bool
          def disposed?
            @disposed
          end
        end

        # Module to be included in classes that need disposal
        module DisposableMixin
          # @rbs return: void
          def dispose
            return if @disposed
            @disposed = true
            perform_dispose
          end

          # @rbs return: bool
          def disposed?
            @disposed ||= false
          end

          protected

          # Override this method to perform cleanup
          # @rbs return: void
          def perform_dispose
            # Default implementation does nothing
          end
        end
      end
    end
  end
end
