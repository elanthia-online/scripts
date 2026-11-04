# frozen_string_literal: true

require_relative 'support/harness'

# The commands the user gives lnet (';chat ...', ';lnet allow ...'), run
# through the real LNet::Commands router. What is sent is read back from the
# fake server; what the user is told is read from the captured output.
RSpec.describe 'lnet.lic commands' do
  let(:server) { LnetSpec::FakeServer.new }

  before do
    lnet.server = server
    allow(lnet::Commands).to receive(:rand).and_return(1) # no 'mad skills' surprise
  end

  def run(line) = LnetSpec.capture { lnet::Commands.run(line) }

  def echoes(out) = out.select { |kind, _| kind == :echo }.map(&:last)

  # @return [Array<Array(String, Hash, Object)>] [tag, attributes, text or payload] for each element sent
  def sent
    server.lines.map do |line|
      element = REXML::Document.new(line).root
      attributes = element.attributes.to_h { |name, attribute| [name, attribute.value] }
      body = element.name == 'data' ? lnet::SafeMarshal.decode(element.text) : element.text
      [element.name, attributes, body]
    end
  end

  describe 'chat' do
    {
      'chat to Bob hi there'      => ['message', { 'type' => 'private', 'to' => 'Bob' }, 'hi there'],
      'chat ::GSIV:Bob hi'        => ['message', { 'type' => 'private', 'to' => 'GSIV:Bob' }, 'hi'],
      'chat on General hi all'    => ['message', { 'type' => 'channel', 'channel' => 'General' }, 'hi all'],
      'chat :General hi'          => ['message', { 'type' => 'channel', 'channel' => 'General' }, 'hi'],
      'chat hello'                => ['message', { 'type' => 'channel' }, 'hello'],
      'chat .to the moon'         => ['message', { 'type' => 'channel' }, 'to the moon'],
      'chat .on second thought'   => ['message', { 'type' => 'channel' }, 'on second thought'],
      'CHAT TO Bob shouting'      => ['message', { 'type' => 'private', 'to' => 'Bob' }, 'shouting'],
      'chat :)'                   => ['message', { 'type' => 'channel' }, ':)']
    }.each do |line, element|
      it "sends #{line.inspect} as #{element.inspect}" do
        run(line)
        expect(sent).to eq([element])
      end
    end

    ['chat ot Bob my secret', 'chat to Bob', 'chat ::Bob', 'chat on General', 'chat'].each do |line|
      it "sends nothing for #{line.inspect}" do
        expect(echoes(run(line)).last).to start_with("You're doing it wrong.")
        expect(server.lines).to be_empty
      end
    end

    it 'replies to whoever sent the last private message' do
      lnet.last_priv = 'GSIV:Ann'
      run('reply sure thing')
      expect(sent).to eq([['message', { 'type' => 'private', 'to' => 'GSIV:Ann' }, 'sure thing']])
    end

    it 'says there is nothing to reply to' do
      expect(echoes(run('reply hello'))).to eq(['No private message to reply to.'])
    end

    ['add alias Bob reply me', 'create channel Help please reply here'].each do |line|
      it "does not take #{line.inspect} for a reply" do
        lnet.last_priv = 'GSIV:Ann'
        run(line)
        expect(sent.map { |tag, attributes, _| [tag, attributes['type']] }).not_to include(['message', 'private'])
      end
    end

    it 'says so when LNet is not connected, instead of dropping the message silently' do
      lnet.server = nil
      expect(echoes(run('chat hello'))).to eq(['LNet is not connected right now; that was not sent.'])
    end
  end

  describe 'queries and requests' do
    {
      'who'               => ['query', { 'type' => 'connected' }, nil],
      'who General'       => ['query', { 'type' => 'connected', 'name' => 'General' }, nil],
      'who GSIV:Bob'      => ['query', { 'type' => 'connected', 'name' => 'GSIV:Bob' }, nil],
      'stats'             => ['query', { 'type' => 'server stats' }, nil],
      'channels'          => ['query', { 'type' => 'channels', 'num' => '15' }, nil],
      'channel'           => ['query', { 'type' => 'channels', 'num' => '15' }, nil],
      'channels full'     => ['query', { 'type' => 'channels' }, nil],
      'tune Help'         => ['tune', { 'channel' => 'Help' }, nil],
      'untune Help'       => ['untune', { 'channel' => 'Help' }, nil],
      'locate bob'        => ['request', { 'type' => 'locate', 'to' => 'Bob' }, nil],
      'SPELLS dr:bob'     => ['request', { 'type' => 'spells', 'to' => 'DR:Bob' }, nil],
      'bounty gsplat:ann' => ['request', { 'type' => 'bounty', 'to' => 'GSPlat:Ann' }, nil]
    }.each do |line, element|
      it "sends #{line.inspect} as #{element.inspect}" do
        run(line)
        expect(sent).to eq([element])
      end
    end

    ['who [Bob]', 'tune Gen_eral', 'locate Bob^', 'channelsfoo'].each do |line|
      it "refuses #{line.inspect}" do
        expect(echoes(run(line)).last).to start_with("You're doing it wrong.")
        expect(server.lines).to be_empty
      end
    end

    it "won't request from someone the user ignores" do
      lnet.options['ignore'] = ['Bob']
      expect(echoes(run('locate GSIV:Bob'))).to eq(["There's no point in sending a request to someone you're ignoring."])
      expect(server.lines).to be_empty
    end
  end

  describe 'friend, enemy and ignore lists' do
    it 'writes names the way LNet does, whatever the game code' do
      run('add friend dr:bob')
      run('add friend gsplat:ann')
      run('add friend gsiv:cid')
      run('addfriend eve')
      expect(lnet.options['friends']).to eq(['DR:Bob', 'GSPlat:Ann', 'GSIV:Cid', 'Eve'])
    end

    it 'matches a DR friend added in lower case when they ask for something' do
      run('add friend dr:bob')
      lnet.options['permission']['bounty'] = 'friends'
      expect(lnet.allow?('bounty', 'DR:Bob')).to be(true)
    end

    it 'adds once, removes, and says what happened' do
      expect(echoes(run('add enemy Mal'))).to eq(['Mal was added to your enemy list.'])
      expect(echoes(run('add enemies mal'))).to eq(['Mal is already on your enemy list.'])
      expect(echoes(run('enemies'))).to eq(['enemies: Mal'])
      expect(echoes(run('del enemy MAL'))).to eq(['Mal was removed from your enemy list.'])
      expect(echoes(run('remove enemy Mal'))).to eq(['Mal was not found on your enemy list.'])
      expect(echoes(run('enemy'))).to eq(['You have no enemies.'])
    end

    it 'ignores and unignores' do
      expect(echoes(run('ignore gsiv:spam'))).to eq(['You are now ignoring GSIV:Spam.'])
      expect(echoes(run('ignore GSIV:Spam'))).to eq(['You were already ignoring GSIV:Spam.'])
      expect(echoes(run('ignore'))).to eq(['You are ignoring the following people: GSIV:Spam'])
      expect(echoes(run('unignore gsiv:spam'))).to eq(['You are no longer ignoring GSIV:Spam.'])
      expect(echoes(run('unignore Spam'))).to eq(["Spam wasn't being ignored."])
      expect(echoes(run('ignore'))).to eq(['You are not ignoring anyone.'])
      expect(echoes(run('friends'))).to eq(['You have no friends.'])
    end
  end

  describe 'list entries saved by an older lnet in another case' do
    it 'finds them when adding and removes them' do
      lnet.options['friends'] = ['dr:Bob']
      expect(echoes(run('add friend DR:Bob'))).to eq(['DR:Bob is already on your friend list.'])
      expect(echoes(run('del friend dr:bob'))).to eq(['DR:Bob was removed from your friend list.'])
      expect(lnet.options['friends']).to be_empty
    end
  end

  describe 'aliases' do
    it 'adds, lists and removes an alias' do
      expect(echoes(run('add alias GSIV:Jeril StrangerDanger'))).to eq(['chats from GSIV:Jeril will now appear as StrangerDanger'])
      run('add alias GSIV:Ann Annie')
      expect(run('aliases')).to eq([[:respond, "\n   GSIV:Jeril => StrangerDanger\n   GSIV:Ann   => Annie\n\n"]])
      expect(echoes(run('del alias StrangerDanger'))).to eq(['alias deleted'])
      expect(lnet.alias).to eq('GSIV:Ann' => 'Annie')
      expect(echoes(run('remove alias Nobody'))).to eq(["couldn't find an alias by that name"])
    end

    it 'warns when the name is not written as the thought window shows it' do
      expect(echoes(run('add alias jeril Stranger')).size).to eq(3)
    end

    it 'says when there are none' do
      expect(echoes(run('aliases'))).to eq(['You have no aliases.'])
    end
  end

  describe 'permissions' do
    it 'names what every permission covers' do
      lnet.options['permission'] = { 'locate' => 'friends', 'health' => 'all', 'info' => 'enemies' }
      lnet.add_callback('roundtime') { 1 }
      lines = run('allow').map(&:last)
      expect(lines).to eq(['You are allowing only your friends to locate you.', 'You are allowing no one to view your active spells.',
                           'You are allowing no one to view your skills.', 'You are allowing everyone except your enemies to view your stats.',
                           'You are allowing everyone to view your health.', 'You are allowing no one to view your bounties.',
                           'You are allowing no one to request your roundtime.'])
      lines.each { |line| expect(line).not_to end_with('to .') }
    end

    { 'all' => 'all', 'friends' => 'friends', 'friend' => 'friends', 'non-enemies' => 'enemies', 'nonenemies' => 'enemies',
      'enemies' => 'enemies', 'none' => 'none', 'NONE' => 'none' }.each do |word, permission|
      it "sets #{permission.inspect} for 'allow locate #{word}'" do
        run("allow locate #{word}")
        expect(lnet.options['permission']).to eq('locate' => permission)
      end
    end

    it 'sets every type, registered ones included, for allow all' do
      lnet.add_callback('roundtime') { 1 }
      run('allow all friends')
      expect(lnet.options['permission'].keys).to contain_exactly('spells', 'skills', 'info', 'locate', 'health', 'bounty', 'roundtime')
      expect(lnet.options['permission'].values.uniq).to eq(['friends'])
    end

    it 'sets a permission for a type a script registered' do
      lnet.add_callback('roundtime') { 1 }
      expect(echoes(run('allow roundtime all'))).to eq(['You are now allowing everyone to request your roundtime.'])
    end

    it 'refuses an unknown type or group without changing anything' do
      expect(echoes(run('allow horoscope all')).first).to start_with('horoscope is not something you can allow.')
      expect(echoes(run('allow locate everybody')).first).to start_with('Who may see it must be one of:')
      expect(lnet.options['permission']).to be_empty
    end
  end

  describe 'options' do
    it 'turns options on and off' do
      expect(echoes(run('timestamps=on'))).to eq(['timestamps will be shown'])
      expect(lnet.options['timestamps']).to be(true)
      expect(echoes(run('famwindow=ON'))).to eq(['chats will be sent to the familiar window'])
      expect(echoes(run('greeting=off'))).to eq(['greeting will not be shown'])
      expect(lnet.options['greeting']).to be(false)
      expect(echoes(run('debug=on'))).to eq(['debug output is on'])
      expect(LnetSpec.capture { lnet.debug('x') }).to eq([[:echo, 'x']])
    end

    it 'sets and clears the highlight preset' do
      run('preset=thoughts')
      expect(lnet.options['preset']).to eq('thought')
      run('preset=nil')
      expect(lnet.options['preset']).to be_nil
      expect(echoes(run('preset=rainbow')).first).to start_with('Unknown option specified for preset')
    end

    it 'changes the password on the server and saves it locally' do
      expect(echoes(run('password=hunter2'))).to eq(['Password saved locally.'])
      expect(sent).to eq([['data', { 'type' => 'newpassword' }, 'hunter2']])
      expect(lnet.login_attributes['password']).to eq('hunter2')
      run('password=nil')
      expect(lnet.login_attributes['password']).to be_nil
    end

    it 'says the server still has the old password when not connected' do
      lnet.server = nil
      expect(echoes(run('password=hunter2'))).to eq(['Password saved locally.', 'LNet is not connected right now, so the server still has the old password.'])
    end
  end

  describe 'channel moderation' do
    {
      'ban GSIV:Bob on General for 2 hours' => { 'action' => 'ban', 'name' => 'GSIV:Bob', 'channel' => 'General', 'length' => '7200' },
      'gag Bob on Help for 30s'             => { 'action' => 'gag', 'name' => 'Bob', 'channel' => 'Help', 'length' => '30' },
      'BANIP Bob on Help for 1y'            => { 'action' => 'banip', 'name' => 'Bob', 'channel' => 'Help', 'length' => '31536000' },
      'ban Bob on Help'                     => { 'action' => 'ban', 'name' => 'Bob', 'channel' => 'Help' },
      'mod Bob on Help'                     => { 'action' => 'mod', 'name' => 'Bob', 'channel' => 'Help' },
      'unmod Bob on Help'                   => { 'action' => 'unmod', 'name' => 'Bob', 'channel' => 'Help' }
    }.each do |line, attributes|
      it "sends #{line.inspect}" do
        run(line)
        expect(sent).to eq([['moderate', attributes, nil]])
      end
    end

    ['ban Bob on Help for 6 months', 'gag Bob on Help for 2 mo', 'ban Bob on Help for 2 decades'].each do |line|
      it "refuses a length in units it does not know: #{line.inspect}" do
        expect(echoes(run(line)).last).to start_with("You're doing it wrong.")
        expect(server.lines).to be_empty
      end
    end

    it 'creates hidden and private channels' do
      run('create hidden private channel Secret  a place for us ')
      expect(sent).to eq([['admin', { 'action' => 'create channel', 'name' => 'Secret', 'description' => 'a place for us',
                                      'hidden' => 'yes', 'private' => 'yes' }, nil]])
    end

    it 'deletes a channel' do
      run('delete channel Secret')
      expect(sent).to eq([['admin', { 'action' => 'delete channel', 'name' => 'Secret' }, nil]])
    end
  end

# Checked at LNet.admin: REXML 3.4 reads an attribute name with a space
# ("option 1") as "option", so on the wire only the last option survives,
# as it always has with this REXML; what the server expects is unknown.
describe 'create poll' do
  def poll_attributes(line)
    captured = nil
    allow(lnet).to receive(:admin) { |attributes| captured = attributes }
    run(line)
    captured
  end

  it 'reads its flags in any order, the vote time included' do
    expect(poll_attributes('create poll --question Best town? --vote-time 5m --option-1 Landing --option-2 Icemule'))
      .to eq('action' => 'create poll', 'question' => 'Best town?', 'option 1' => 'Landing', 'option 2' => 'Icemule', 'length' => '300')
  end

  it 'stops at the first missing option number and trims long text' do
    attributes = poll_attributes("create poll --option-1 a --option-2 #{'b' * 100} --option-4 d --question #{'q' * 600}")
    expect(attributes.keys).to contain_exactly('action', 'question', 'option 1', 'option 2')
    expect(attributes['option 2'].length).to eq(64)
    expect(attributes['question'].length).to eq(512)
  end

  ['create poll --question Lonely? --option-1 only', 'create poll --option-1 a --option-2 b'].each do |line|
    it "refuses #{line.inspect}" do
      expect(echoes(run(line)).last).to start_with("You're doing it wrong.")
      expect(server.lines).to be_empty
    end
  end
end

  describe 'help' do
    it 'shows help for help and for nothing at all' do
      [run('help'), run(''), run('  ')].each do |out|
        expect(out.size).to eq(1)
        expect(out.first[1]).to include(';chat <message>', ';lnet allow <action> <group>', ';lnet debug=<on/off>')
      end
    end

    it 'says how to get help for anything it does not know' do
      expect(echoes(run('frobnicate'))).to eq(["You're doing it wrong.  Type ;lnet help"])
    end
  end
end
