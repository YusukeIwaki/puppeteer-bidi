# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Page.pdf", type: :integration do
  describe "followSymlinks" do
    it "should reject PDF output to an existing symlink path" do
      with_test_state do |page:, server:, **|
        begin
          tmpdir = Dir.mktmpdir("pptr-symlink-")
          target_file = File.join(tmpdir, "output.pdf")
          link_file = File.join(tmpdir, "output-link.pdf")
          File.binwrite(target_file, "placeholder")
          File.symlink(target_file, link_file)
        rescue SystemCallError, NotImplementedError
          skip "symlinks are not supported on this platform"
        end

        begin
          Puppeteer::Bidi.set_follow_symlinks(false)
          page.goto(server.empty_page)

          expect { page.pdf(path: link_file) }.to raise_error(Errno::ELOOP)
        ensure
          Puppeteer::Bidi.set_follow_symlinks(true)
          FileUtils.rm_rf(tmpdir)
        end
      end
    end
  end
end
