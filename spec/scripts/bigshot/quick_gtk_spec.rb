# frozen_string_literal: true

# Optional real GTK rendering, with no Lich boot, character files or game IO:
# BIGSHOT_GTK_SMOKE=1 xvfb-run -a rspec spec/scripts/bigshot/quick_gtk_spec.rb
# Uses the production Setup constructor, XML, Quick widgets and save/destroy
# handlers. Only legacy profile loading/tooltips and Lich's GUI queue are stubbed.
if ENV['BIGSHOT_GTK_SMOKE'] == '1'
  require 'gtk3'
  require 'yaml'

  module BigshotQuickGtkSpec
    CharSettings = {}
    def CharSettings.active_scope
      'GSIV:OfflineFixture'
    end

    module Settings
      def self.root_proxy_for(_scope)
        CharSettings
      end
    end
    UserVars = Struct.new(:op).new({})
    module Lich
      module Messaging
        class << self
          attr_accessor :messages

          def msg(_style, message)
            messages << message
          end
        end
      end
    end

    source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
    %w[EncounterSettings QuickRequest].each do |name|
      module_eval(source[/^  class #{name}\n.*?^  end$/m], __FILE__, __LINE__)
    end
    module_eval(source[/^  class Setup < Gtk::Builder\n.*?^  end$/m], __FILE__, __LINE__)
  end
end

RSpec.describe 'Bigshot Quick real GTK setup', :gtk do
  before do
    skip 'Set BIGSHOT_GTK_SMOKE=1 under xvfb-run for real GTK rendering' unless ENV['BIGSHOT_GTK_SMOKE'] == '1'
    allow(Gtk).to receive(:queue) { |&block| block.call }
    allow_any_instance_of(BigshotQuickGtkSpec::Setup).to receive(:load_settings)
    allow_any_instance_of(BigshotQuickGtkSpec::Setup).to receive(:set_tooltips)
    BigshotQuickGtkSpec::CharSettings.clear
    BigshotQuickGtkSpec::UserVars.op = { 'profile_current' => 'fixture-profile' }
    BigshotQuickGtkSpec::Lich::Messaging.messages = []
    @editor = BigshotQuickGtkSpec::Setup.new(profile_current: 'fixture-profile')
    @window = @editor['main']
    @notebook = @editor['bigshot_notebook']
    @window.show_all
    @notebook.page = @notebook.n_pages - 1
    drain_events
  end

  after do
    @window&.destroy unless @window&.destroyed?
    drain_events if defined?(Gtk) && ENV['BIGSHOT_GTK_SMOKE'] == '1'
  end

  def drain_events
    # GTK frame-clock allocation and X configure/delete events are asynchronous.
    # Keep one bounded turn of the real event loop instead of assuming a resize
    # has completed merely because the immediate event queue is empty.
    finished = false
    GLib::Timeout.add(50) do
      finished = true
      false
    end
    Gtk.main_iteration until finished
  end

  def field(name)
    @editor.instance_variable_get("@quick_trial_#{name}")
  end

  def children(widget)
    [widget] + (widget.respond_to?(:children) ? widget.children.flat_map { |child| children(child) } : [])
  end

  def stage_edits
    @editor.instance_variable_get(:@encounter_fields).fetch('fallback_commands').text = 'unarmed jab'
    @editor.instance_variable_get(:@encounter_fields).fetch('area').active_id = 'profile'
    field('name').text = 'fixture-trial'
    field('commands').buffer.text = "unarmed jab\nunarmed punch"
    field('max_actions').text = '4'
    field('max_seconds').text = '30'
    button = children(@window).find { |widget| widget.is_a?(Gtk::Button) && widget.label == 'Save trial' }
    button.clicked
    expect(BigshotQuickGtkSpec::CharSettings).to be_empty
  end

  [800, 720].each do |height|
    it "renders usable preset and trial controls within a 1080x#{height} window by scrolling" do
      @window.resize(1080, height)
      drain_events
      scroll = @notebook.get_nth_page(@notebook.page)
      expect(@notebook.get_tab_label(scroll).text).to eq('Quick Combat')
      expect(@window.allocated_width).to be <= 1080
      expect(@window.allocated_height).to be <= height
      expect(scroll.hadjustment.upper).to be <= scroll.hadjustment.page_size
      expect(scroll.vadjustment.upper).to be > scroll.vadjustment.page_size
      expect(@editor.instance_variable_get(:@encounter_fields).fetch('mode').allocated_width).to be >= 150
      scroll.vadjustment.value = scroll.vadjustment.upper - scroll.vadjustment.page_size
      drain_events
      %w[name commands max_actions max_seconds].each do |name|
        widget = field(name)
        expect(widget.visible?).to be(true)
        expect(widget.allocated_width).to be >= 150
        _x, y = widget.translate_coordinates(scroll, 0, 0)
        expect(y).to be >= 0
        expect(y + widget.allocated_height).to be <= scroll.allocated_height
      end
      warn "GTK allocation: window #{@window.allocated_width}x#{@window.allocated_height}; page #{scroll.allocated_width}x#{scroll.allocated_height}; content #{scroll.hadjustment.upper.to_i}x#{scroll.vadjustment.upper.to_i}; trial editor #{field('commands').allocated_width}x#{field('commands').allocated_height}"
    end
  end

  it 'round-trips staged preset and trial edits through the actual Close button' do
    stage_edits
    button = children(@window).find { |widget| widget.is_a?(Gtk::Button) && widget.label == 'Close' }
    button.clicked
    drain_events
    expect(@window.destroyed?).to be(true)
    stored = BigshotQuickGtkSpec::CharSettings.fetch('bigshot_encounters')
    restored = BigshotQuickGtkSpec::EncounterSettings.new(stored)
    expect(restored.preset.fetch('fallback_commands')).to eq('unarmed jab')
    expect(restored.preset.fetch('area')).to eq('profile')
    expect(restored.trial('fixture-trial')).to include('actions' => ['unarmed jab', 'unarmed punch'], 'max_actions' => 4, 'max_seconds' => 30)
    expect(BigshotQuickGtkSpec::UserVars.op.fetch('profile_current')).to eq('fixture-profile')
    expect(BigshotQuickGtkSpec::Lich::Messaging.messages).to include(' Bigshot UI closed, saving any changes')
  end

  it 'discards staged preset and trial edits through the GTK window-close event' do
    stage_edits
    @window.close
    drain_events
    expect(@window.destroyed?).to be(true)
    expect(BigshotQuickGtkSpec::CharSettings).to be_empty
    expect(BigshotQuickGtkSpec::UserVars.op).to eq('profile_current' => 'fixture-profile')
    expect(BigshotQuickGtkSpec::Lich::Messaging.messages).to include(' Bigshot UI closed WITHOUT saving any changes')
  end
end
