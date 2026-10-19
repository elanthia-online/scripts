# frozen_string_literal: true

# Spec for lich5-update.lic's request routing, with the focus on --beta.
#
# The whole real script is evaluated, top to bottom, inside a fresh anonymous
# module per example, the way Lich runs it: the version check at the top, the
# legacy Lich5Update module, and the final `Lich5Update.request(...)` call.
# Constants the script reads (LICH_VERSION, Script, Lich::Util::Update, URI,
# the *_DIR paths) resolve lexically to stand-ins defined on that module, so
# nothing leaks into other specs. The client connections are real UNIX socket
# pairs installed as $_CLIENT_ / $_DETACHABLE_CLIENT_ (saved and restored
# around every example).
#
# Lich always loads its NilClass patch (nil.strip returns ""), and rspec does
# not, so the legacy examples run twice: once on plain Ruby and once with the
# patch's methods from the pinned lich-5 checkout applied as a refinement
# scoped to the evaluated script. A refinement cannot carry the patch's
# method_missing, so nil.gets still raises in that mode.

require 'json'
require 'socket'
require 'timeout'
require 'tmpdir'
require 'fileutils'
require_relative '../spec_helper'

module Lich5UpdateSpec
  SOURCE_PATH = find_lic_source('lich5-update.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH)

  nil_source = read_lich5_source('lib/common/class_exts/nilclass.rb')
  nil_body = nil_source && nil_source[/^class NilClass\n(.*)^end/m, 1]
  NIL_PATCH = (Module.new { refine(NilClass) { module_eval(nil_body) } } if nil_body)

  # Module#using refuses to run when the eval is called from inside a method,
  # so the evaluation goes through a lambda defined outside any method.
  EVALUATE = ->(mod, source, path, line) { mod.module_eval(source, path, line) }

  BETA_RELEASES = JSON.generate(
    [{ 'tag_name' => 'v5.99.0-beta.1',
       'body'     => "Beta notes\n## What's Changed\n* x",
       'assets'   => [{ 'name' => 'lich-5.tar.gz', 'browser_download_url' => 'https://example.invalid/beta.tar.gz' }] }]
  )

  # Records every call the script makes to Lich's own updater.
  class CoreUpdate
    attr_reader :calls

    def initialize
      @calls = []
    end

    def request(arg)
      @calls << [:request, arg]
    end

    def download_update
      @calls << [:download_update]
    end
  end

  # Stand-in for URI: records every URL opened and serves canned bodies.
  class FakeURI
    attr_reader :opened

    def initialize(bodies)
      @bodies = bodies
      @opened = []
    end

    def parse(url)
      uri = self
      Object.new.tap do |o|
        o.define_singleton_method(:open) do
          uri.opened << url.to_s
          body = uri.body_for(url.to_s)
          Struct.new(:read).new(body)
        end
      end
    end

    def body_for(url)
      @bodies.fetch(url) { raise "unexpected URL opened: #{url}" }
    end
  end

  # One evaluation of the real script.
  class Run
    attr_reader :mod, :output, :core, :uri, :dirs

    # ruby_version stands in for RUBY_VERSION as the script sees it, so the
    # examples do not depend on the Ruby running rspec.
    def initialize(lich_version:, arg:, nil_patch: false, uri_bodies: {}, ruby_version: '4.0.7')
      @output = []
      @core = CoreUpdate.new
      @uri = FakeURI.new(uri_bodies)
      @dirs = %w[SCRIPT_DIR LIB_DIR DATA_DIR TEMP_DIR BACKUP_DIR LICH_DIR].to_h { |c| [c, Dir.mktmpdir(c.downcase)] }
      @nil_patch = nil_patch
      @mod = build_module(lich_version, arg, ruby_version)
    end

    def call(timeout: 3)
      prefix = @nil_patch ? "using Lich5UpdateSpec::NIL_PATCH\n" : ''
      Timeout.timeout(timeout) do
        EVALUATE.call(@mod, prefix + SOURCE, SOURCE_PATH, @nil_patch ? 0 : 1)
      rescue SystemExit
        @exited = true
      end
      self
    end

    def exited?
      @exited == true
    end

    def text
      @output.join("\n")
    end

    def cleanup
      @dirs.each_value { |d| FileUtils.rm_rf(d) }
    end

    private

    def build_module(lich_version, arg, ruby_version)
      mod = Module.new
      mod.const_set(:LICH_VERSION, lich_version)
      mod.const_set(:RUBY_VERSION, ruby_version)
      script = Struct.new(:vars).new(arg.nil? ? [] : [arg])
      mod.const_set(:Script, Module.new.tap { |s| s.define_singleton_method(:current) { script } })
      core = @core
      lich = Module.new
      util = Module.new
      update = Module.new
      update.define_singleton_method(:request) { |a| core.request(a) }
      update.define_singleton_method(:download_update) { core.download_update }
      util.const_set(:Update, update)
      lich.const_set(:Util, util)
      mod.const_set(:Lich, lich)
      mod.const_set(:URI, @uri)
      @dirs.each { |name, dir| mod.const_set(name, dir) }

      # Pre-create the script's module so its implicit-self calls land on
      # stand-ins: respond/_respond record output, and require is a no-op so
      # gem_check never depends on what this machine has installed.
      out = @output
      legacy = Module.new
      legacy.define_singleton_method(:respond) { |*a| out << a.join("\n") }
      legacy.define_singleton_method(:_respond) { |*a| out << a.join("\n") }
      legacy.define_singleton_method(:require) { |*_a| true }
      mod.const_set(:Lich5Update, legacy)
      mod
    end
  end
end

RSpec.describe 'lich5-update.lic' do
  around do |example|
    saved = [$_CLIENT_, $_DETACHABLE_CLIENT_]
    begin
      example.run
    ensure
      $_CLIENT_, $_DETACHABLE_CLIENT_ = saved
    end
  end

  let(:runs) { [] }
  let(:sockets) { [] }

  after do
    runs.each(&:cleanup)
    sockets.each { |s| s.close unless s.closed? }
  end

  def run_script(**kwargs)
    Lich5UpdateSpec::Run.new(**kwargs).tap { |r| runs << r }
  end

  # A client connection with lines already typed and waiting. Returns the
  # end the script sees and the user's end.
  def client_with(*lines)
    script_end, user_end = UNIXSocket.pair
    sockets.push(script_end, user_end)
    lines.each { |l| user_end.write("#{l}\n") }
    [script_end, user_end]
  end

  # Every line still unread on the script's end of a connection.
  def unread(script_end, user_end)
    user_end.close_write
    script_end.read.lines.map(&:chomp)
  end

  shared_examples 'legacy beta request' do |nil_patch|
    let(:releases_url) { 'https://api.github.com/repos/elanthia-online/lich-5/releases' }

    let(:guide) { 'https://github.com/elanthia-online/lich-5/wiki/Documentation-for-Installing-and-Upgrading-Lich' }

    def legacy_run(arg, nil_patch, ruby_version: '4.0.7')
      run_script(lich_version: '5.6.2', arg: arg, nil_patch: nil_patch, ruby_version: ruby_version,
                 uri_bodies: { releases_url => Lich5UpdateSpec::BETA_RELEASES })
    end

    def expect_refusal(run, ruby_version: '4.0.7')
      expect(run.text).to include('Beta testing needs Lich 5.7.0 or newer.')
      expect(run.text).to include("You are running Lich 5.6.2 on Ruby #{ruby_version}.")
      expect(run.text).to include(";lich5-update --update' to install the current release first")
      expect(run.text).to include(guide)
      expect(run.text).not_to match(/;send/i)
      expect(run.core.calls).to be_empty
      expect(run.uri.opened).to be_empty
    end

    # Current Lich exits at startup on Ruby older than 4.0, so an older Ruby
    # must not be pointed at --update.
    def expect_ruby_refusal(run, ruby_version)
      expect(run.text).to include('Beta testing needs Lich 5.7.0 or newer.')
      expect(run.text).to include("You are running Lich 5.6.2 on Ruby #{ruby_version}.")
      expect(run.text).to include('Current Lich releases need Ruby 4.0 or newer')
      expect(run.text).to include(guide)
      expect(run.text).not_to include('--update')
      expect(run.text).not_to match(/;send/i)
      expect(run.core.calls).to be_empty
      expect(run.uri.opened).to be_empty
    end

    ['2.7.8', '3.4.1', '3.4.9'].each do |ruby_version|
      ['--beta', '--test'].each do |arg|
        it "#{arg} on Ruby #{ruby_version} sends the user to the install guide, not to --update" do
          script_end, user_end = client_with(';send Y')
          $_CLIENT_ = script_end
          $_DETACHABLE_CLIENT_ = nil

          run = legacy_run(arg, nil_patch, ruby_version: ruby_version).call

          expect(unread(script_end, user_end)).to eq([';send Y'])
          expect_ruby_refusal(run, ruby_version)
        end
      end
    end

    it '--beta on Ruby 4.0.0 (the boundary) still suggests --update' do
      expect_refusal(legacy_run('--beta', nil_patch, ruby_version: '4.0.0').call, ruby_version: '4.0.0')
    end

    it '--beta leaves typed lines on the primary client unread and installs nothing' do
      script_end, user_end = client_with('look', ';send Y', 'inventory')
      $_CLIENT_ = script_end
      $_DETACHABLE_CLIENT_ = nil

      run = legacy_run('--beta', nil_patch).call

      expect(unread(script_end, user_end)).to eq(['look', ';send Y', 'inventory'])
      expect_refusal(run)
    end

    it '--beta leaves both clients untouched when a detachable client is also connected' do
      primary, primary_user = client_with('look')
      detached, detached_user = client_with(';send Y')
      $_CLIENT_ = primary
      $_DETACHABLE_CLIENT_ = detached

      run = legacy_run('--beta', nil_patch).call

      expect(unread(primary, primary_user)).to eq(['look'])
      expect(unread(detached, detached_user)).to eq([';send Y'])
      expect_refusal(run)
    end

    it '--beta leaves lines on a detachable-only client unread' do
      detached, detached_user = client_with(';s y', 'look')
      $_CLIENT_ = nil
      $_DETACHABLE_CLIENT_ = detached

      run = legacy_run('--beta', nil_patch).call

      expect(unread(detached, detached_user)).to eq([';s y', 'look'])
      expect_refusal(run)
    end

    it '--beta returns at once when nothing has been typed' do
      script_end, user_end = client_with
      $_CLIENT_ = script_end
      $_DETACHABLE_CLIENT_ = nil

      run = legacy_run('--beta', nil_patch)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run.call(timeout: 2)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(elapsed).to be < 1
      expect(unread(script_end, user_end)).to eq([])
      expect_refusal(run)
    end

    it '--beta with no client connected still answers' do
      $_CLIENT_ = nil
      $_DETACHABLE_CLIENT_ = nil

      expect_refusal(legacy_run('--beta', nil_patch).call)
    end

    ['--test', '--beta --confirm', '--test --confirm', '--beta confirm'].each do |arg|
      it "#{arg} gets the same answer and reads nothing" do
        script_end, user_end = client_with(';send Y')
        $_CLIENT_ = script_end
        $_DETACHABLE_CLIENT_ = nil

        run = legacy_run(arg, nil_patch).call

        expect(unread(script_end, user_end)).to eq([';send Y'])
        expect_refusal(run)
      end
    end

    it '--beta --library=<name> still fetches that one file from the staging branch' do
      script_end, user_end = client_with(';send Y')
      $_CLIENT_ = script_end
      $_DETACHABLE_CLIENT_ = nil
      staging = 'https://raw.githubusercontent.com/elanthia-online/lich-5/staging/lib/foo.rb'
      run = run_script(lich_version: '5.6.2', arg: '--beta --library=foo.rb', nil_patch: nil_patch,
                       uri_bodies: { staging => "# staged\n" })

      run.call

      expect(run.uri.opened).to eq([staging])
      expect(File.read(File.join(run.dirs['LIB_DIR'], 'foo.rb'))).to eq("# staged\n")
      expect(run.text).to include('foo.rb has been updated.')
      expect(run.text).not_to include('Beta testing needs')
      expect(run.core.calls).to be_empty
      expect(unread(script_end, user_end)).to eq([';send Y'])
    end
  end

  context 'on Lich 5.6.2 (the legacy module runs)' do
    context 'on plain Ruby' do
      include_examples 'legacy beta request', false
    end

    context "with Lich's NilClass patch" do
      before { skip 'no lich-5 checkout (set LICH5_PATH)' unless Lich5UpdateSpec::NIL_PATCH }

      include_examples 'legacy beta request', true
    end

    it '--update still goes to the legacy updater, not to Lich::Util::Update' do
      latest = 'https://api.github.com/repos/elanthia-online/lich-5/releases/latest'
      release = JSON.generate('tag_name' => 'v5.6.2', 'body' => 'notes',
                              'assets' => [{ 'name' => 'lich-5.tar.gz', 'browser_download_url' => 'https://example.invalid/r.tar.gz' }])
      run = run_script(lich_version: '5.6.2', arg: '--update', uri_bodies: { latest => release }).call

      expect(run.uri.opened).to eq([latest])
      expect(run.text).to include('Lich version 5.6.2 is good.')
      expect(run.core.calls).to be_empty
    end
  end

  # Lich 5.5 and older ship no Lich::Util::Update (lib/update.rb first appears
  # in 5.6.0), and on 5.6.x it is only loaded once the built-in command has run.
  context 'when Lich::Util::Update is not defined (Lich 5.5 and older)' do
    [['plain Ruby', false], ["Lich's NilClass patch", true]].each do |label, nil_patch|
      it "--beta answers on Lich 5.5.0 without touching Lich::Util::Update (#{label})" do
        skip 'no lich-5 checkout (set LICH5_PATH)' if nil_patch && !Lich5UpdateSpec::NIL_PATCH
        script_end, user_end = client_with(';send Y')
        $_CLIENT_ = script_end
        $_DETACHABLE_CLIENT_ = nil
        releases_url = 'https://api.github.com/repos/elanthia-online/lich-5/releases'
        run = run_script(lich_version: '5.5.0', arg: '--beta', nil_patch: nil_patch,
                         uri_bodies: { releases_url => Lich5UpdateSpec::BETA_RELEASES })
        run.mod::Lich::Util.send(:remove_const, :Update)

        expect { run.call }.not_to raise_error

        expect(run.text).to include('Beta testing needs Lich 5.7.0 or newer.')
        expect(run.text).to include('You are running Lich 5.5.0 on Ruby 4.0.7.')
        expect(run.uri.opened).to be_empty
        expect(unread(script_end, user_end)).to eq([';send Y'])
      end
    end
  end

  context 'on Lich 5.7.0 and newer (Lich installs betas itself)' do
    ['5.7.0', '5.21.0'].each do |version|
      ['--beta', '--beta --confirm', '--test confirm', '--beta --library=foo.rb'].each do |arg|
        it "#{version}: hands '#{arg}' to Lich::Util::Update unchanged and exits" do
          script_end, user_end = client_with(';send Y')
          $_CLIENT_ = script_end
          $_DETACHABLE_CLIENT_ = nil

          run = run_script(lich_version: version, arg: arg).call

          expect(run.exited?).to be(true)
          expect(run.core.calls).to eq([[:request, arg]])
          expect(run.output).to be_empty
          expect(run.uri.opened).to be_empty
          expect(unread(script_end, user_end)).to eq([';send Y'])
        end
      end
    end

    it 'with no argument asks Lich::Util::Update to announce' do
      run = run_script(lich_version: '5.21.0', arg: nil).call

      expect(run.exited?).to be(true)
      expect(run.core.calls).to eq([[:request, '--announce']])
    end
  end
end
