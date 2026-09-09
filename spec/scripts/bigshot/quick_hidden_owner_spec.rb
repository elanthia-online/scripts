# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

RSpec.describe 'Quick ownership through a hidden native parent' do
  it 'admits its hidden child but excludes a second hidden Bigshot owner' do
    skip 'Set LICH_EXECUTION_GUARD_ROOT for native ownership integration' unless ENV['LICH_EXECUTION_GUARD_ROOT']

    probe = <<~'RUBY'
      require 'json'
      require 'set'
      require 'tmpdir'
      require 'fileutils'
      LIB_DIR = File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib')
      $LOAD_PATH.unshift(LIB_DIR)
      %w[common/script common/limitedarray common/sharedbuffer].each { |file| require file }
      Object.include Lich::Common
      module Lich
        def self.log(_message); end
      end
      def respond(*); end
      $_CLIENTBUFFER_ = LimitedArray.new
      module Probe; end
      source = File.read(ARGV.fetch(0)).gsub("\r\n", "\n")
      Probe.module_eval(source[/^  class QuickStartup\n.*?^  end$/m])
      RESULT = {}
      Dir.mktmpdir('quick-hidden-owner') do |root|
        Object.const_set(:SCRIPT_DIR, root)
        FileUtils.mkdir_p(File.join(root, 'custom'))
        File.write(File.join(root, 'custom', 'bigshot.lic'), <<~'CHILD')
          owner = Script.current
          RESULT[:hidden] = owner.hidden
          RESULT[:visible] = Script.running.include?(owner)
          RESULT[:listed] = Script.list.include?(owner)
          RESULT[:admitted] = Probe::QuickStartup.owner_available?(owner)
          rival = Script.subscript { sleep 5 }
          rival.define_singleton_method(:name) { 'bigshot-copy' }
          RESULT[:rival_hidden] = rival.hidden
          RESULT[:conflict_rejected] = !Probe::QuickStartup.owner_available?(owner)
          rival.kill
          rival.join(2)
        CHILD
        parent = Script.subscript do
          Script.current.hidden = true
          child = Script.start_child('bigshot', '', quiet: true)
          raise 'child timed out' unless child && child.join(3)
          raise 'child failed' unless child.completed_successfully?
        end
        raise 'parent timed out' unless parent.join(5)
        RESULT[:parent_success] = parent.completed_successfully?
        RESULT[:remaining] = Script.list.map(&:name)
      end
      puts JSON.generate(RESULT)
    RUBY
    output, error, status = Open3.capture3(RbConfig.ruby, '-', File.expand_path('../../../scripts/bigshot.lic', __dir__), stdin_data: probe)
    expect(status.success?).to be(true), "#{output}\n#{error}"
    expect(JSON.parse(output)).to eq('hidden' => true, 'visible' => false, 'listed' => true,
                                     'admitted' => true, 'rival_hidden' => true, 'conflict_rejected' => true,
                                     'parent_success' => true, 'remaining' => [])
  end
end
