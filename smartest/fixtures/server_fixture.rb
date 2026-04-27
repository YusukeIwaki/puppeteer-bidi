# frozen_string_literal: true

# Provides shared HTTP/HTTPS test servers.
#
# The underlying `TestServer::Server` instances are launched once per suite and
# torn down at the end (`suite_fixture` scope). The test-scoped `server` and
# `https_server` fixtures hand out the same instances but additionally clear
# any custom routes/CSP/request-promises that the previous test registered, so
# tests start with a clean server state without paying the start-up cost.
class ServerFixture < Smartest::Fixture
  suite_fixture :_shared_test_server do
    server = TestServer::Server.new
    server.start
    cleanup { server.stop }
    server
  end

  suite_fixture :_shared_https_test_server do
    server = TestServer::Server.new(scheme: "https", ssl_context: TestServer.ssl_context)
    server.start
    cleanup { server.stop }
    server
  end

  fixture :server do |_shared_test_server:|
    cleanup { _shared_test_server.clear_routes }
    _shared_test_server
  end

  fixture :https_server do |_shared_https_test_server:|
    cleanup { _shared_https_test_server.clear_routes }
    _shared_https_test_server
  end
end
