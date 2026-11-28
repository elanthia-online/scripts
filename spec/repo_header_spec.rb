# frozen_string_literal: true

require_relative 'spec_helper'

# The Lich repository only parses a script's header (description, author,
# game, version:) out of the first 20,000 bytes of the uploaded file -- the
# same limit repository.lic's own upload path uses. A header block whose
# closing `=end` falls past that point uploads without any error, but the
# server records no header and no version, so `;repository info` shows a blank
# description and the version list silently stops at the last good upload
# (this happened to bigshot.lic from v5.16.0 on).
#
# Run repository.lic's real CommentParser over both the first 20,000 bytes and
# the whole file; any difference means the server would lose the header.
RSpec.describe 'repository header limit' do
  header_scan_limit = 20_000

  repo_source_path = File.join(REPO_ROOT, 'scripts', 'repository.lic')
  parser_source = extract_from_source(
    File.read(repo_source_path),
    /^  class CommentParser\n.*?^  end\n/m,
    label: 'CommentParser',
    source_path: repo_source_path
  )
  comment_parser = Module.new.module_eval("#{parser_source.gsub(/^  /, '')}\nCommentParser", repo_source_path)

  # Same file selection as bin/repo's publish step.
  published = Dir[File.join(REPO_ROOT, 'scripts', '**', '*')]
              .select { |f| File.file?(f) && f =~ /\.(rb|lic|xml|ui)$/ }
              .sort

  published.each do |path|
    name = path.delete_prefix("#{REPO_ROOT}/")

    it "#{name} keeps its whole header within the first #{header_scan_limit} bytes" do
      data = File.binread(path)
      full = comment_parser.extract_comments(data)
      scanned = comment_parser.extract_comments(data[0, header_scan_limit])

      expect(scanned).to eq(full), lambda {
        end_at = data.index(/^=end/)
        "#{name}: the repository server only reads the first #{header_scan_limit} bytes for the header, " \
          "but this header ends at byte #{end_at || 'unknown'}. It would publish with no description and no version. " \
          'Shorten the header (e.g. trim old changelog entries) so it ends well before that point.'
      }
    end
  end
end
