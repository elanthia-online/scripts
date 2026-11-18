# frozen_string_literal: true

require "digest/sha1"
require "erb"
require "fileutils"
require "json"
require "open3"

# Builds the jinx repository index (manifest.json + headers/) for a folder of
# assets. Output is the same shape jinxp v0.4.0 produced, which is the
# contract scripts/jinx.lic reads:
#
#   - every asset's "file" is "/assets/<basename>": jinx downloads it from
#     repo url + file, so the publish step must serve the asset folder at
#     /assets (the Pages workflow symlinks dist/assets -> ../scripts rather
#     than copying anything)
#   - "md5" is really a base64 SHA1 of the file bytes; jinx compares it with
#     Digest::SHA1#base64digest, so keep the name and the algorithm
#   - "header", "version" and "author" are omitted when absent; "tags" is
#     always present
#
# Only the manifest and headers are written. Assets are never copied.
module JinxManifest
  HEADER_PATTERN  = /^=begin\r?\n?(.+?)^=end/m
  TAGS_PATTERN    = /^[\s\t#]*tags: (.*?)$/i
  VERSION_PATTERN = /^[\s\t#]*version: (.*)$/i
  AUTHOR_PATTERN  = /^[\s\t#]*author: (.*)$/i

  ENGINES    = %w[lich.rb].freeze
  SCRIPT_EXT = %w[.lic .rb].freeze
  MAP_EXT    = %w[.gif .jpg .png].freeze

  module_function

  # Writes <output>/manifest.json and <output>/headers/*.header for every
  # non-hidden file directly inside input. Returns the manifest hash.
  def build(input:, output:, now: Time.now.to_i)
    headers_dir = File.join(output, "headers")
    FileUtils.mkdir_p(headers_dir)

    assets = Dir.children(input).sort
                .reject { |name| name.start_with?(".") }
                .map { |name| File.join(input, name) }
                .select { |path| File.file?(path) }
                .map { |path| entry(path, headers_dir, now) }

    manifest = { "available" => assets, "last_updated" => now }
    File.write(File.join(output, "manifest.json"), JSON.generate(manifest))
    manifest
  end

  def entry(path, headers_dir, now)
    name   = File.basename(path)
    source = File.binread(path)
    asset  = {
      "file"        => "/assets/#{url_encode(name)}",
      "type"        => type_for(name),
      "md5"         => Digest::SHA1.base64digest(source),
      "last_commit" => last_commit(path) || now,
    }
    meta = asset["type"] == "script" ? header_meta(name, source, headers_dir) : {}

    asset["header"]  = meta[:header] if meta[:header]
    asset["tags"]    = meta[:tags] || []
    asset["version"] = meta[:version] if meta[:version]
    asset["author"]  = meta[:author] if meta[:author]
    asset
  end

  def type_for(name)
    ext = File.extname(name).downcase
    return "engine" if ENGINES.include?(name)
    return "script" if SCRIPT_EXT.include?(ext)
    return "map" if MAP_EXT.include?(ext)

    "data"
  end

  # Parses the leading =begin/=end block, writes it to headers/, and returns
  # its tags/version/author. A script without a header gets no header file.
  def header_meta(name, source, headers_dir)
    text = source.dup.force_encoding(Encoding::UTF_8)
    text = source.b unless text.valid_encoding?
    header = text[HEADER_PATTERN, 1]
    return {} if header.nil?

    header_file = "#{name.gsub('.lic', '')}.header"
    File.binwrite(File.join(headers_dir, header_file), header)

    lines = header.each_line(chomp: true).to_a
    {
      header: "/headers/#{header_file}",
      # limit -1 keeps a trailing "" for "a, b," exactly as jinxp did
      tags: first_capture(lines, TAGS_PATTERN)&.strip&.split(",", -1)&.map { |tag| utf8(tag.strip) },
      version: utf8(first_capture(lines, VERSION_PATTERN)&.strip),
      author: utf8(first_capture(lines, AUTHOR_PATTERN)&.strip),
    }
  end

  # Manifest JSON must be UTF-8; a header in another encoding (the header
  # file itself keeps its exact bytes) gets U+FFFD for the bad bytes.
  def utf8(value)
    value&.dup&.force_encoding(Encoding::UTF_8)&.scrub
  end

  def first_capture(lines, pattern)
    lines.each do |line|
      match = line.match(pattern)
      return match[1] if match
    end
    nil
  end

  # Author date of the last commit touching path, or nil when git has none
  # (untracked file, or not a git checkout).
  def last_commit(path)
    out, status = Open3.capture2("git", "log", "-1", "--date=unix", "--format=%ad", "--", File.basename(path),
                                 chdir: File.dirname(path), err: File::NULL)
    stamp = out.strip
    status.success? && !stamp.empty? ? Integer(stamp) : nil
  rescue SystemCallError
    nil
  end

  # Percent-encodes a filename for a URL path; jinx CGI.unescape's it back.
  def url_encode(name)
    ERB::Util.url_encode(name)
  end
end
