# Spec for ebounty.lic's open_container: a container may only land on the
# close-at-exit list when LOOK IN said it was closed and OPEN didn't say it
# was already open. Replies are taken from a player's logs, including a stray
# game line arriving where the OPEN reply was expected.
#
# Also covers find_herb_stow_list: a forage bounty names a mushroom by its
# short name ("golden mushroom") while the foraged item carries the full name
# ("golden hook mushroom"), so the short name must map to the full one or the
# foraged count stays at 0.
#
# Also covers forage_not_found_regex: every "herb isn't here" forage reply must
# match it, or the forage never sees a result, waits out the roundtime and
# forages again in the same room forever.

require_relative '../spec_helper'

module EBountySpec
  SOURCE_PATH = find_lic_source('ebounty.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")
  METHOD_SRC = extract_lic_method(SOURCE, 'open_container', source_path: SOURCE_PATH)
  HERB_METHOD_SRC = extract_lic_method(SOURCE, 'find_herb_stow_list', source_path: SOURCE_PATH)
  NOT_FOUND_METHOD_SRC = extract_lic_method(SOURCE, 'forage_not_found_regex', source_path: SOURCE_PATH)
end

Object.send(:remove_const, :EBounty) if defined?(EBounty)
module EBounty
  # Nested so the real top-level GameObj is never touched (see spec_helper).
  module GameObj
    def self.containers = @containers ||= {}
  end

  # Nested for the same reason: find_herb_stow_list resolves StowList here.
  module StowList
    def self.stow_list = @stow_list ||= {}
  end

  Data = Struct.new(:close_containers)
  Container = Struct.new(:id, :name, :noun, :contents)
  Item = Struct.new(:name)

  class << self
    attr_accessor :replies, :sent

    def data = @data ||= Data.new([])
    def msg(*) = nil

    def get_command(command, _regex, **)
      sent << command
      replies.fetch(command.split.first, [])
    end
  end

  module_eval(EBountySpec::METHOD_SRC)
  module_eval(EBountySpec::HERB_METHOD_SRC)
  module_eval(EBountySpec::NOT_FOUND_METHOD_SRC)
end

RSpec.describe 'EBounty.open_container' do
  id = '948868120'
  let(:case_obj) { EBounty::Container.new(id, 'grey wood case', 'case', nil) }

  before do
    EBounty.data.close_containers = []
    EBounty.sent = []
    EBounty::GameObj.containers.clear
  end

  def run(look:, open: [])
    EBounty.replies = { 'look' => look, 'open' => open }
    allow(EBounty).to receive(:sleep)
    EBounty.open_container(case_obj)
  end

  it 'never opens or closes a container LOOK IN shows is open' do
    run(look: [%(In the <a exist="#{id}" noun="case">grey wood case</a> you see a <a exist="1" noun="die">die</a>.)])
    expect(EBounty.sent).to eq(["look in ##{id}"])
    expect(EBounty.data.close_containers).to be_empty
  end

  it 'treats an empty open container as open' do
    run(look: ['There is nothing in there.'])
    expect(EBounty.sent).to eq(["look in ##{id}"])
  end

  it 'closes it at exit when it was closed and a custom message opened it' do
    run(look: ['That is closed.'],
        open: ['You reach over your shoulder and open the grey wood case, being careful not to spill the contents.'])
    expect(EBounty.data.close_containers).to eq([id])
  end

  it 'does not close a stray line\'s container: OPEN said it was already open' do
    run(look: ['That is closed.'], open: ['A semblance of warmth returns to your limbs.', 'That is already open.'])
    expect(EBounty.data.close_containers).to be_empty
  end

  it 'does not close it on the XML "is open already" reply' do
    run(look: [], open: [%(The <a exist="#{id}" noun="shard">shard</a> is open already.)])
    expect(EBounty.data.close_containers).to be_empty
  end

  it 'does not close it when LOOK IN never said it was closed' do
    run(look: [], open: ['You wave a hand across the shard, and it shimmers briefly as a piece of itself disappears like mist, forming an opening.'])
    expect(EBounty.data.close_containers).to be_empty
  end

  it 'skips the game entirely when the container is already known open' do
    EBounty::GameObj.containers[id] = []
    case_obj.contents = []
    run(look: [])
    expect(EBounty.sent).to be_empty
  end
end

RSpec.describe 'EBounty.find_herb_stow_list' do
  def stow(*names)
    EBounty::StowList.stow_list[:default] = EBounty::Container.new('1', 'boarhide pack', 'pack', names.map { |n| EBounty::Item.new(n) })
  end

  after { EBounty::StowList.stow_list.clear }

  {
    'white mushroom'    => 'white hook mushroom',
    'trafel mushroom'   => 'black trafel mushroom',
    'withered mushroom' => 'withered black mushroom',
    'soft mushroom'     => 'soft white mushroom',
    'red mushroom'      => 'red trafel mushroom',
    'black mushroom'    => 'black hook mushroom',
    'golden mushroom'   => 'golden hook mushroom',
  }.each do |bounty_name, item_name|
    it "counts #{item_name} for a #{bounty_name} bounty" do
      stow(item_name, item_name, 'some acantha leaf')
      expect(EBounty.find_herb_stow_list(bounty_name).map(&:name)).to eq([item_name, item_name])
    end
  end

  it 'maps the bounty name regardless of case' do
    stow('golden hook mushroom')
    expect(EBounty.find_herb_stow_list('Golden Mushroom').length).to eq(1)
  end

  it 'does not count other hook mushrooms for a golden mushroom bounty' do
    stow('white hook mushroom', 'black hook mushroom')
    expect(EBounty.find_herb_stow_list('golden mushroom')).to be_empty
  end

  it 'still matches a full golden hook mushroom name directly' do
    stow('golden hook mushroom')
    expect(EBounty.find_herb_stow_list('golden hook mushroom').length).to eq(1)
  end
end

RSpec.describe 'EBounty.forage_not_found_regex' do
  [
    # Wrong climate for the herb, from a player's log.
    'As you carefully forage around you find no trace of what you are looking for.  ' \
    'You are not even sure it could be found in this type of climate.',
    'As you carefully forage around you can find no hint of what you are looking for right now, ' \
    'though you are fairly certain this is where it can be found.',
    'As you carefully forage around you can find no trace of what you are looking for.  ' \
    'You briefly wonder if it could even thrive in this place.',
    'As you carefully forage around you see no evidence of what you are looking for.',
  ].each do |line|
    it "matches: #{line[0, 70]}..." do
      expect(line).to match(EBounty.forage_not_found_regex)
    end
  end

  it 'does not match a successful forage' do
    expect('You forage briefly and manage to find a strand of seaweed!').not_to match(EBounty.forage_not_found_regex)
  end
end
