# Spec for ebounty.lic's open_container: a container may only land on the
# close-at-exit list when LOOK IN said it was closed and OPEN didn't say it
# was already open. Replies are taken from a player's logs, including a stray
# game line arriving where the OPEN reply was expected.

require_relative '../spec_helper'

module EBountySpec
  SOURCE_PATH = find_lic_source('ebounty.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")
  METHOD_SRC = extract_lic_method(SOURCE, 'open_container', source_path: SOURCE_PATH)
end

Object.send(:remove_const, :EBounty) if defined?(EBounty)
module EBounty
  # Nested so the real top-level GameObj is never touched (see spec_helper).
  module GameObj
    def self.containers = @containers ||= {}
  end

  Data = Struct.new(:close_containers)
  Container = Struct.new(:id, :name, :noun, :contents)

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
