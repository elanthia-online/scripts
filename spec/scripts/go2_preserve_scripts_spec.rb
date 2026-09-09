# frozen_string_literal: true

# Exercise go2's actual option parser and auxiliary-script handling, without
# connecting to a game or substituting a different navigation implementation.
RSpec.describe 'go2 one-trip auxiliary-script preservation' do
  let(:source) { File.read(ENV.fetch('GO2_SOURCE') { File.expand_path('../../scripts/go2.lic', __dir__) }) }
  let(:settings) { {} }

  before do
    stub_const('CharSettings', settings)
    stub_const('XMLData', double(game: 'GSIV'))
    stub_const('Script', Class.new)
    allow(Script).to receive(:running?).and_return(true)
  end

  def parse(arguments)
    allow(Script).to receive(:current).and_return(double(vars: ['go2', *arguments]))
    parser = source[/^  target_search_array\s+=.*?^  target_search_string = target_search_array.join\(' '\)/m]
    raise 'go2 option parser missing' unless parser

    Object.new.instance_eval("setting_value = {'on' => true, 'off' => false}\n#{parser}\n[target_search_string, defined?(setting_preserve_scripts) ? setting_preserve_scripts : false]")
  end

  def auxiliary_actions(preserve)
    handler = source[/^    if !setting_preserve_scripts && Script.running\?\('roomnumbers'\).*?(?=^    if XMLData.game)/m]
    raise 'go2 auxiliary-script block missing' unless handler

    stub_const('Room', Class.new)
    allow(Room).to receive(:current).and_return(double(id: 100))
    allow(Room).to receive(:[]).with(100).and_return(double(tags: ['peer']))
    allow(Room).to receive(:[]).with(101).and_return(double(tags: ['ordinary']))
    actions = []
    scope = Object.new
    scope.define_singleton_method(:stop_script) { |name| actions << [:stop, name] }
    scope.define_singleton_method(:start_script) { |name| actions << [:start, name] }
    scope.define_singleton_method(:before_dying) { |&callback| callback.call }
    scope.instance_eval("setting_preserve_scripts = #{preserve}; path = [101]; est_time = 10\n#{handler}")
    actions
  end

  it 'parses the one-trip flag without saving settings or changing the target' do
    expect(parse(['132', '--preserve-scripts'])).to eq(['132', true])
    expect(settings).to eq({})
  end

  it 'defaults to existing auxiliary handling' do
    expect(parse(['132'])).to eq(['132', false])
    expect(auxiliary_actions(false)).to eq([
                                             [:stop, 'roomnumbers'], [:start, 'roomnumbers'],
                                             [:stop, 'textsubs'], [:start, 'textsubs']
                                           ])
  end

  it 'does not stop or restart either auxiliary script on a preserved trip' do
    expect(auxiliary_actions(true)).to eq([])
  end

  it 'does not persist the flag across independent trips' do
    expect(parse(['132', '--preserve-scripts']).last).to be(true)
    expect(parse(['223']).last).to be(false)
  end

  it 'preserves the numeric destination with the full supervised go2 argument list' do
    arguments = %w[132 --disable-confirm --typeahead=0 --stop-for-dead=off --get-silvers=off --hide-room-descriptions=off --hide-room-titles=off --preserve-scripts]
    expect(parse(arguments)).to eq(['132', true])
    expect(settings).to eq({})
  end
end
