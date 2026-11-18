# frozen_string_literal: true

require "json"
require "tmpdir"
require "digest/sha1"
require_relative "../../lib/jinx_manifest"

RSpec.describe JinxManifest do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      @input = File.join(dir, "scripts")
      @output = File.join(dir, "dist")
      Dir.mkdir(@input)
      example.run
    end
  end

  def write_asset(name, body)
    File.binwrite(File.join(@input, name), body)
  end

  def git(*args)
    system("git", *args, chdir: @dir, out: File::NULL, err: File::NULL) or raise "git #{args.join(' ')} failed"
  end

  def build(now: 1_700_000_000)
    described_class.build(input: @input, output: @output, now: now)
  end

  def asset(manifest, basename)
    manifest["available"].find { |a| File.basename(a["file"]) == basename }
  end

  let(:header_body) do
    <<~HEADER
        A test script.

          author: Someone
            tags: hunting, utility,
         version: 1.2.3
    HEADER
  end

  it "describes a script with a header the way jinx.lic reads it" do
    source = "=begin\n#{header_body}=end\nputs 1\n"
    write_asset("demo.lic", source)

    entry = asset(build, "demo.lic")

    expect(entry).to eq(
      "file"        => "/assets/demo.lic",
      "type"        => "script",
      "md5"         => Digest::SHA1.base64digest(source),
      "last_commit" => 1_700_000_000,
      "header"      => "/headers/demo.header",
      "tags"        => ["hunting", "utility", ""],
      "version"     => "1.2.3",
      "author"      => "Someone",
    )
    expect(File.binread(File.join(@output, "headers", "demo.header"))).to eq(header_body)
  end

  it "omits header/version/author for a script with no header, but keeps tags" do
    write_asset("bare.lic", "puts 1\n")

    entry = asset(build, "bare.lic")

    expect(entry.keys).to eq(%w[file type md5 last_commit tags])
    expect(entry["tags"]).to eq([])
    expect(Dir.children(File.join(@output, "headers"))).to be_empty
  end

  it "types data, map and engine assets without parsing headers" do
    write_asset("spell-list.xml", "=begin\nversion: 9\n=end\n")
    write_asset("map.png", "png")
    write_asset("lich.rb", "=begin\nversion: 5\n=end\n")

    manifest = build

    expect(asset(manifest, "spell-list.xml")).to include("type" => "data", "tags" => [])
    expect(asset(manifest, "spell-list.xml")).not_to have_key("version")
    expect(asset(manifest, "map.png")["type"]).to eq("map")
    expect(asset(manifest, "lich.rb")["type"]).to eq("engine")
  end

  it "names a .rb script's header after the full basename" do
    write_asset("tool.rb", "=begin\nversion: 1\n=end\n")

    expect(asset(build, "tool.rb")["header"]).to eq("/headers/tool.rb.header")
  end

  it "percent-encodes names so jinx can CGI.unescape them back" do
    write_asset("my script.lic", "puts 1\n")

    entry = build["available"].first

    expect(entry["file"]).to eq("/assets/my%20script.lic")
    expect(CGI.unescape(File.basename(entry["file"]))).to eq("my script.lic")
  end

  it "skips hidden files and subdirectories" do
    write_asset(".hidden.lic", "puts 1\n")
    Dir.mkdir(File.join(@input, "nested"))
    write_asset("real.lic", "puts 1\n")

    expect(build["available"].map { |a| a["file"] }).to eq(["/assets/real.lic"])
  end

  it "still writes the header of a script that isn't valid UTF-8" do
    latin1_e = [0xE9].pack("C")
    source = "=begin\nversion: 2\nauthor: caf#{latin1_e}\n=end\n".b
    write_asset("latin1.lic", source)

    entry = asset(build, "latin1.lic")

    expect(entry["version"]).to eq("2")
    expect(entry["author"]).to eq("caf#{[0xFFFD].pack('U')}")
    expect(File.binread(File.join(@output, "headers", "latin1.header"))).to eq("version: 2\nauthor: caf#{latin1_e}\n".b)
  end

  it "uses the author date of the last commit that touched each file" do
    git("init", "-q")
    write_asset("old.lic", "puts 1\n")
    git("add", ".")
    git("-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", "old",
        "--date=@1600000000 +0000")
    write_asset("new.lic", "puts 2\n")

    manifest = build(now: 1_800_000_000)

    expect(asset(manifest, "old.lic")["last_commit"]).to eq(1_600_000_000)
    expect(asset(manifest, "new.lic")["last_commit"]).to eq(1_800_000_000)
  end

  it "writes manifest.json with the available list and last_updated" do
    write_asset("demo.lic", "puts 1\n")

    build(now: 42)
    written = JSON.parse(File.read(File.join(@output, "manifest.json")))

    expect(written.keys).to eq(%w[available last_updated])
    expect(written["last_updated"]).to eq(42)
    expect(written["available"].size).to eq(1)
  end
end
