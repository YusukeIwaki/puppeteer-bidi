# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "time"

ROOT = Pathname.new(__dir__).join("..").expand_path
CACHE_SCHEMA_VERSION = 1

def run_capture(*command, chdir: nil)
  output = if chdir
    IO.popen(command, chdir: chdir.to_s, err: %i[child out], &:read)
  else
    IO.popen(command, err: %i[child out], &:read)
  end
  status = $?
  raise "Command failed: #{command.join(" ")}\n#{output}" unless status&.success?

  output
end

def read_puppeteer_commit(puppeteer_dir)
  run_capture("git", "rev-parse", "HEAD", chdir: puppeteer_dir.to_s).strip
rescue StandardError
  "unknown"
end

def find_puppeteer_doc_paths(puppeteer_dir)
  candidates = []

  api_md = puppeteer_dir.join("docs/api.md")
  candidates << api_md if api_md.file?

  api_dir = puppeteer_dir.join("docs/api")
  if api_dir.directory?
    Dir.glob(api_dir.join("**/*.md")).sort.each do |path|
      candidates << Pathname.new(path)
    end
  end

  candidates.uniq
end

def extract_frontmatter_value(markdown, key)
  in_frontmatter = false
  markdown.each_line do |line|
    stripped = line.strip
    if stripped == "---"
      in_frontmatter = !in_frontmatter
      next
    end
    next unless in_frontmatter

    next unless stripped.start_with?("#{key}:")

    value = stripped.delete_prefix("#{key}:").strip
    value = value[1..-2] if (value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'"))
    return value.strip
  end
  nil
end

def extract_heading_api_references(markdown, source:)
  refs = []

  markdown.each_line do |line|
    next unless line.start_with?("#")

    heading = line.sub(/\A#+\s+/, "").strip
    next if heading.empty?

    token = heading.split(/[\s(:—-]/, 2).first.to_s.strip
    next if token.empty?
    next if token.start_with?("event:", "type:", "class:", "interface:")

    token = token.delete_suffix("method")
    token = token.delete_suffix("property")
    token = token.delete_suffix("class")
    token = token.delete_suffix("()")
    token = token.sub(/\Anew\s+/, "")
    token = token[1..-2] if token.start_with?("`") && token.end_with?("`") && token.length >= 2

    owner = nil
    member = nil

    if token.include?(".")
      owner, member = token.split(".", 2)
    elsif token.include?("#")
      owner, member = token.split("#", 2)
    end

    next if owner.nil? || member.nil?
    next if owner.empty? || member.empty?

    refs << { "owner" => owner, "member" => member, "source" => source }
  end

  refs
end

def extract_puppeteer_api(puppeteer_dir)
  doc_paths = find_puppeteer_doc_paths(puppeteer_dir)
  raise "Could not find Puppeteer docs under #{puppeteer_dir}" if doc_paths.empty?

  entries = []
  doc_paths.each do |path|
    markdown = path.read
    rel = path.relative_path_from(puppeteer_dir).to_s

    sidebar_label = extract_frontmatter_value(markdown, "sidebar_label")
    if sidebar_label && (sidebar_label.include?(".") || sidebar_label.include?("#"))
      token = sidebar_label.strip
      token = token[1..-2] if token.start_with?("`") && token.end_with?("`") && token.length >= 2
      owner = nil
      member = nil
      if token.include?(".")
        owner, member = token.split(".", 2)
      elsif token.include?("#")
        owner, member = token.split("#", 2)
      end
      if owner && member && !owner.empty? && !member.empty?
        entries << { "owner" => owner, "member" => member, "source" => rel }
        next
      end
    end

    entries.concat(extract_heading_api_references(markdown, source: rel))
  end

  dedup = {}
  entries.each do |e|
    key = "#{e["owner"]}.#{e["member"]}"
    dedup[key] ||= e
  end

  dedup.values.sort_by { |e| [e["owner"].downcase, e["member"].downcase] }
end

def camel_to_snake(name)
  name
    .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
    .gsub(/([a-z\d])([A-Z])/, '\1_\2')
    .tr("-", "_")
    .downcase
end

SPECIAL_MEMBER_MAPPINGS = {
  "$" => "query_selector",
  "$$" => "query_selector_all",
  "$eval" => "eval_on_selector",
  "$$eval" => "eval_on_selector_all",
  "waitForSelector" => "wait_for_selector",
  "waitForXPath" => "wait_for_xpath",
  "waitForFunction" => "wait_for_function",
  "waitForNavigation" => "wait_for_navigation",
  "waitForRequest" => "wait_for_request",
  "waitForResponse" => "wait_for_response",
  "waitForFileChooser" => "wait_for_file_chooser",
  "evaluateHandle" => "evaluate_handle",
  "evaluateOnNewDocument" => "evaluate_on_new_document",
  "setContent" => "set_content",
  "setViewport" => "set_viewport",
  "setUserAgent" => "set_user_agent",
  "setExtraHTTPHeaders" => "set_extra_http_headers",
  "isClosed" => "closed?"
}.freeze

def ruby_member_candidates(node_member)
  mapped = SPECIAL_MEMBER_MAPPINGS[node_member]
  return [mapped] if mapped

  snake = camel_to_snake(node_member)
  candidates = [snake]

  if snake.start_with?("is_") && !snake.end_with?("?")
    candidates << "#{snake.delete_prefix("is_")}?"
  end

  candidates.uniq
end

NODE_OWNER_ALIASES = {
  "puppeteer" => "Puppeteer",
  "Puppeteer" => "Puppeteer",
  "PuppeteerNode" => "Puppeteer",
  "browser" => "Browser",
  "Browser" => "Browser",
  "browsercontext" => "BrowserContext",
  "browserContext" => "BrowserContext",
  "BrowserContext" => "BrowserContext",
  "page" => "Page",
  "Page" => "Page",
  "frame" => "Frame",
  "Frame" => "Frame",
  "elementhandle" => "ElementHandle",
  "elementHandle" => "ElementHandle",
  "ElementHandle" => "ElementHandle",
  "jshandle" => "JSHandle",
  "jsHandle" => "JSHandle",
  "JSHandle" => "JSHandle",
  "keyboard" => "Keyboard",
  "Keyboard" => "Keyboard",
  "mouse" => "Mouse",
  "Mouse" => "Mouse",
  "httprequest" => "HTTPRequest",
  "httpRequest" => "HTTPRequest",
  "HTTPRequest" => "HTTPRequest",
  "httpresponse" => "HTTPResponse",
  "httpResponse" => "HTTPResponse",
  "HTTPResponse" => "HTTPResponse",
  "filechooser" => "FileChooser",
  "fileChooser" => "FileChooser",
  "FileChooser" => "FileChooser"
  # Note: Target is excluded from coverage tracking due to significant
  # implementation differences between Node.js and Ruby versions.
}.freeze

def canonical_node_owner(owner)
  NODE_OWNER_ALIASES[owner] || NODE_OWNER_ALIASES[owner.downcase] || owner
end

RUBY_OWNER_CONSTANTS = {
  "Puppeteer" => "Puppeteer::Bidi",
  "Browser" => "Puppeteer::Bidi::Browser",
  "BrowserContext" => "Puppeteer::Bidi::BrowserContext",
  "Page" => "Puppeteer::Bidi::Page",
  "Frame" => "Puppeteer::Bidi::Frame",
  "ElementHandle" => "Puppeteer::Bidi::ElementHandle",
  "JSHandle" => "Puppeteer::Bidi::JSHandle",
  "Keyboard" => "Puppeteer::Bidi::Keyboard",
  "Mouse" => "Puppeteer::Bidi::Mouse",
  "HTTPRequest" => "Puppeteer::Bidi::HTTPRequest",
  "HTTPResponse" => "Puppeteer::Bidi::HTTPResponse",
  "FileChooser" => "Puppeteer::Bidi::FileChooser"
  # Note: Target is excluded from coverage tracking due to significant
  # implementation differences between Node.js and Ruby versions.
}.freeze

def safe_constantize(name)
  name.split("::").inject(Object) { |mod, const_name| mod.const_get(const_name) }
rescue NameError
  nil
end

def extract_ruby_public_api
  $LOAD_PATH.unshift(ROOT.join("lib").to_s)
  require "puppeteer/bidi"

  api = {}
  lib_root = ROOT.join("lib").to_s

  RUBY_OWNER_CONSTANTS.each do |label, const_name|
    constant = safe_constantize(const_name)
    next unless constant

    if constant.is_a?(Module) && !constant.is_a?(Class)
      methods = constant.singleton_methods(true).map(&:to_s)
      methods.select! do |method_name|
        method_obj = constant.method(method_name)
        owner_name = method_obj.owner.name
        owner_name&.start_with?("Puppeteer::Bidi") ||
          (method_obj.source_location && method_obj.source_location.first.start_with?(lib_root))
      rescue NameError
        false
      end
      api[label] = { kind: :module, const_name: const_name, methods: methods.sort.uniq }
      next
    end

    methods = constant.public_instance_methods(true).map(&:to_s)
    methods.select! do |method_name|
      owner_name = constant.instance_method(method_name).owner.name
      owner_name&.start_with?("Puppeteer::Bidi")
    rescue NameError
      false
    end
    api[label] = { kind: :class, const_name: const_name, methods: methods.sort.uniq }
  end

  api
end

def load_cache(cache_file, expected_commit:)
  return nil unless cache_file.file?

  data = JSON.parse(cache_file.read)
  return nil unless data.is_a?(Hash)
  return nil unless data["schema_version"] == CACHE_SCHEMA_VERSION
  return nil unless data["puppeteer_commit"] == expected_commit

  entries = data["entries"]
  return nil unless entries.is_a?(Array)

  entries
rescue JSON::ParserError
  nil
end

def write_cache(cache_file, puppeteer_commit:, entries:)
  cache_file.parent.mkpath
  payload = {
    "schema_version" => CACHE_SCHEMA_VERSION,
    "puppeteer_commit" => puppeteer_commit,
    "generated_at" => Time.now.utc.iso8601,
    "entries" => entries
  }
  cache_file.write(JSON.pretty_generate(payload) + "\n")
end

def generate_markdown(puppeteer_commit:, entries:, ruby_api:)
  supported_owners = RUBY_OWNER_CONSTANTS.keys.to_h { |k| [k, true] }
  filtered = entries.select { |e| supported_owners[canonical_node_owner(e["owner"])] }
  grouped = filtered.group_by { |e| canonical_node_owner(e["owner"]) }

  total = 0
  supported = 0

  sections = []

  grouped.keys.sort_by(&:downcase).each do |node_owner_label|
    group = grouped.fetch(node_owner_label)
    ruby_owner_const = RUBY_OWNER_CONSTANTS[node_owner_label]
    ruby_owner = ruby_owner_const ? ruby_api[node_owner_label] : nil

    heading = ruby_owner_const ? "#{node_owner_label} (#{ruby_owner_const})" : node_owner_label
    section_lines = []
    section_lines << "## #{heading}"
    section_lines << ""
    section_lines << "| Node.js | Ruby | Supported |"
    section_lines << "| --- | --- | :---: |"

    ruby_methods = ruby_owner ? ruby_owner.fetch(:methods) : []
    ruby_kind = ruby_owner ? ruby_owner.fetch(:kind) : nil

    group.sort_by { |e| e["member"].downcase }.each do |entry|
      node_owner = entry.fetch("owner")
      node_member = entry.fetch("member")
      node_ref = "#{node_owner}.#{node_member}"

      ruby_candidates = ruby_member_candidates(node_member)
      ruby_supported_method = ruby_candidates.find { |m| ruby_methods.include?(m) }

      total += 1
      if ruby_supported_method
        supported += 1
      end

      ruby_ref = "-"
      if ruby_owner_const && ruby_candidates.any?
        separator = ruby_kind == :module ? "." : "#"
        ruby_method_name = ruby_supported_method || ruby_candidates.first
        ruby_ref = "#{ruby_owner_const}#{separator}#{ruby_method_name}"
      end

      status = ruby_supported_method ? "✅" : "❌"
      section_lines << "| `#{node_ref}` | `#{ruby_ref}` | #{status} |"
    end

    section_lines << ""
    sections << section_lines.join("\n")
  end

  coverage = total.zero? ? 0.0 : (supported.to_f / total) * 100.0
  lines = []
  lines << "# API Coverage"
  lines << ""
  lines << "- Puppeteer commit: `#{puppeteer_commit}`"
  lines << "- Generated by: `development/generate_api_coverage.rb`"
  lines << "- Coverage: `#{supported}/#{total}` (`#{format("%.2f", coverage)}%`)"
  lines << ""
  lines << sections.join("\n")

  lines.join("\n") + "\n"
end

options = {
  puppeteer_dir: ROOT.join("development", "puppeteer").to_s,
  cache_dir: ROOT.join("development", "cache").to_s,
  output: ROOT.join("API_COVERAGE.md").to_s
}

OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby development/generate_api_coverage.rb [options]"
  opts.on("--puppeteer-dir=PATH", "Path to a checked out puppeteer/puppeteer repo") { |v| options[:puppeteer_dir] = v }
  opts.on("--cache-dir=PATH", "Cache directory (default: development/cache)") { |v| options[:cache_dir] = v }
  opts.on("--output=PATH", "Output path (default: API_COVERAGE.md)") { |v| options[:output] = v }
end.parse!

puppeteer_dir = Pathname.new(options.fetch(:puppeteer_dir)).expand_path
cache_dir = Pathname.new(options.fetch(:cache_dir)).expand_path
output_path = Pathname.new(options.fetch(:output)).expand_path

raise "Puppeteer repo not found: #{puppeteer_dir}" unless puppeteer_dir.directory?

puppeteer_commit = read_puppeteer_commit(puppeteer_dir)
cache_file = cache_dir.join("puppeteer_api.json")

entries = load_cache(cache_file, expected_commit: puppeteer_commit)
unless entries
  entries = extract_puppeteer_api(puppeteer_dir)
  write_cache(cache_file, puppeteer_commit: puppeteer_commit, entries: entries)
end

ruby_api = extract_ruby_public_api
output_path.write(
  generate_markdown(
    puppeteer_commit: puppeteer_commit,
    entries: entries,
    ruby_api: ruby_api
  )
)
