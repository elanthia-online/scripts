# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'Quick preset native settings persistence' do
  it 'persists a GTK save to the real character/script SQLite namespace' do
    skip 'Requires BIGSHOT_GTK_SMOKE=1 and LICH_EXECUTION_GUARD_ROOT' unless ENV['BIGSHOT_GTK_SMOKE'] == '1' && ENV['LICH_EXECUTION_GUARD_ROOT']

    probe = File.expand_path('../support/bigshot_quick_settings_probe.rb', __dir__)
    source = File.expand_path('../../scripts/bigshot.lic', __dir__)
    output, error, status = Open3.capture3(RbConfig.ruby, probe, ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), source)
    expect(status.success?).to be(true), "Native GTK save failed:\n#{output}\n#{error}"
  end
end
