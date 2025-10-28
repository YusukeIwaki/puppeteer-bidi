# frozen_string_literal: true

module Puppeteer
  module Bidi
    module Core
      # Disposable provides resource management and cleanup capabilities
      # Similar to TypeScript's DisposableStack
      module Disposable
        # DisposableStack manages multiple disposable resources
        class DisposableStack
          def initialize
            @disposed = false
            @resources = []
          end

          # Add a disposable resource to the stack
          # @param resource [Object] Resource that responds to #dispose
          # @return [Object] The resource itself for convenience
          def use(resource)
            raise 'DisposableStack already disposed' if @disposed
            @resources << resource
            resource
          end

          # Dispose all resources in reverse order (LIFO)
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

          def disposed?
            @disposed
          end
        end

        # Module to be included in classes that need disposal
        module DisposableMixin
          def dispose
            return if @disposed
            @disposed = true
            perform_dispose
          end

          def disposed?
            @disposed ||= false
          end

          protected

          # Override this method to perform cleanup
          def perform_dispose
            # Default implementation does nothing
          end
        end
      end
    end
  end
end
