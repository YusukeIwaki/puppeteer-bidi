# frozen_string_literal: true

class ServerFixture < Smartest::Fixture
  suite_fixture :test_server do
    server = TestServer::Server.new
    server.start
    cleanup do
      server.stop
      puts "[Test Suite] Server stopped"
    end
    puts "[Test Suite] Server started (will be reused across tests)"
    server
  end

  suite_fixture :test_https_server do
    server = TestServer::Server.new(
      scheme: "https",
      ssl_context: TestServer.ssl_context
    )
    server.start
    cleanup do
      server.stop
      puts "[Test Suite] HTTPS server stopped"
    end
    puts "[Test Suite] HTTPS server started (will be reused across tests)"
    server
  end

  fixture :server do |test_server:|
    cleanup { test_server.clear_routes }
    test_server
  end

  fixture :https_server do |test_https_server:|
    cleanup { test_https_server.clear_routes }
    test_https_server
  end
end
