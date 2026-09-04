# frozen_string_literal: true

require_relative '../spec_helper'

# elogin.lic cannot be required directly: it wraps its logic in `module
# ELogin` but reaches for Lich-injected globals and Lich::Common::* modules
# at load time, and its final lines (the version guard and `ELogin.run`)
# execute immediately on load. Instead, the real method bodies are extracted
# from the shipped .lic file (via spec_helper.rb's shared extraction
# helpers) and module_eval'd onto one shared Harness namespace alongside
# small recording stand-ins for the collaborators they call, so these specs
# exercise production code and fail if that code's shape changes, without
# needing the full Lich runtime.
#
# Everything lives under ELoginSpec, not the true top level, so this file
# can't collide with another spec's SOURCE/SOURCE_PATH/Harness -- the same
# reasoning spec/scripts/ledger_spec.rb documents for its own
# LedgerRollingSpec wrapper.
module ELoginSpec
  SOURCE_PATH = find_lic_source('elogin.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")

  def self.extract(name)
    extract_lic_method(SOURCE, name, source_path: SOURCE_PATH)
  end

  DEBUG_LOG_SRC = extract('debug_log')
  HANDLE_ERROR_SRC = extract('handle_error')
  LOG_OPERATION_SRC = extract('log_operation')
  ENSURE_ENTRY_DATA_SRC = extract('ensure_entry_data!')
  EXTRACT_FRONTEND_FLAG_SRC = extract('extract_frontend_flag')
  EXTRACT_CUSTOM_LAUNCH_FLAG_SRC = extract('extract_custom_launch_flag')
  ADD_LOGIN_ENTRY_SRC = extract('add_login_entry')
  MODIFY_LOGIN_ENTRY_SRC = extract('modify_login_entry')
  DELETE_LOGIN_ENTRY_SRC = extract('delete_login_entry')
  PARSE_ARGUMENTS_SRC = extract('parse_arguments')
  RUN_SRC = extract('run')
  LOAD_YAML_ENTRIES_SRC = extract('load_yaml_entries')

  # elogin.lic's Saga support only matters if it agrees with what a real
  # lich-5 release actually implements (which frontends --saga/--frontend=
  # accept, and when Saga conflicts with --custom-launch). Rather than
  # hand-mirror that and risk silently drifting from the real thing, this
  # pulls it from a local lich-5 checkout -- see spec_helper.rb's
  # lich5_path/read_lich5_source and .github/workflows/rspec_tests.yaml for
  # the pinned release CI checks out. LICH5_PATH is nil, and the specs that
  # need this skip gracefully, when no checkout is available locally.
  LICH5_PATH = lich5_path

  if LICH5_PATH
    LOGIN_HELPERS_PATH = File.join(LICH5_PATH, 'lib/common/authentication/login_helpers.rb')
    LOGIN_HELPERS_SOURCE = read_lich5_source('lib/common/authentication/login_helpers.rb')
    SAGA_LAUNCH_POLICY_PATH = File.join(LICH5_PATH, 'lib/common/saga_launch_policy.rb')
    SAGA_LAUNCH_POLICY_SOURCE = read_lich5_source('lib/common/saga_launch_policy.rb')

    FRONTEND_PATTERN_LINE = extract_from_source(
      LOGIN_HELPERS_SOURCE, /^\s*FRONTEND_PATTERN\s*=.*$/,
      label: 'FRONTEND_PATTERN', source_path: LOGIN_HELPERS_PATH
    )
    VALID_GAME_CODES_LINE = extract_from_source(
      LOGIN_HELPERS_SOURCE, /^\s*VALID_GAME_CODES\s*=.*$/,
      label: 'VALID_GAME_CODES', source_path: LOGIN_HELPERS_PATH
    )
    SAGA_LAUNCH_POLICY_BODY = extract_from_source(
      SAGA_LAUNCH_POLICY_SOURCE, /^    module SagaLaunchPolicy\n[\s\S]*?^    end$/,
      label: 'SagaLaunchPolicy module', source_path: SAGA_LAUNCH_POLICY_PATH
    )
  end

  # Mirrors lich-5's Frontend.canonical_name closely enough for the frontend
  # names these specs use (none of which have aliases). Kept as a small
  # hand-written stand-in rather than pulled from the pinned checkout: the
  # real implementation depends on a private alias registry populated by a
  # large, unrelated frontend-definition table, which would add real setup
  # cost here for no coverage value.
  module Frontend
    def self.canonical_name(name)
      name.to_s.downcase
    end
  end

  # Raised by Harness's stand-in `exit` so specs can assert that a code path
  # called handle_error(..., should_exit: true) without actually killing the
  # test process.
  class ExitCalled < StandardError; end

  # One shared harness, matching elogin.lic's own shape (self. methods
  # calling each other via bare references) so the extracted bodies resolve
  # each other exactly as they do in the real module. Per-example state
  # (the call log, the debug flag) is reset by .reset! -- see the `before`
  # hook below.
  module Harness
    class << self
      attr_accessor :debug_messaging

      def calls
        @calls ||= []
      end

      def reset!
        @calls = []
        @debug_messaging = false
      end

      def echo(*msgs)
        calls << [:echo, msgs.first]
      end

      def exit
        raise ExitCalled, 'exit called'
      end

      def save_entry_data(entry_data)
        calls << [:save, entry_data.dup]
      end
    end

    module Lich
      class << self
        def debug_messaging
          Harness.debug_messaging
        end

        def log(msg)
          Harness.calls << [:lich_log, msg]
        end
      end

      module Messaging
        def self.msg(type, text)
          Harness.calls << [:messaging, type, text]
        end
      end

      module Common
        Frontend = ELoginSpec::Frontend

        module Authentication
          module LoginHelpers
            module_eval(ELoginSpec::FRONTEND_PATTERN_LINE) if ELoginSpec::LICH5_PATH
            module_eval(ELoginSpec::VALID_GAME_CODES_LINE) if ELoginSpec::LICH5_PATH
          end
        end

        # Real, pinned-release source (see ELoginSpec above) -- not
        # hand-mirrored.
        module_eval(ELoginSpec::SAGA_LAUNCH_POLICY_BODY) if ELoginSpec::LICH5_PATH
      end
    end

    module Script
      NAME = 'elogin'

      class << self
        def current
          self
        end

        def name
          NAME
        end

        def pause
          Harness.calls << [:pause]
        end
      end
    end

    CharSettings = {}.freeze

    module_eval(ELoginSpec::DEBUG_LOG_SRC, ELoginSpec::SOURCE_PATH)
    module_eval(ELoginSpec::HANDLE_ERROR_SRC, ELoginSpec::SOURCE_PATH)
    module_eval(ELoginSpec::LOG_OPERATION_SRC, ELoginSpec::SOURCE_PATH)
    module_eval(ELoginSpec::ENSURE_ENTRY_DATA_SRC, ELoginSpec::SOURCE_PATH)
    module_eval(ELoginSpec::EXTRACT_FRONTEND_FLAG_SRC, ELoginSpec::SOURCE_PATH)
    module_eval(ELoginSpec::EXTRACT_CUSTOM_LAUNCH_FLAG_SRC, ELoginSpec::SOURCE_PATH)
    module_eval(ELoginSpec::ADD_LOGIN_ENTRY_SRC, ELoginSpec::SOURCE_PATH)
    module_eval(ELoginSpec::MODIFY_LOGIN_ENTRY_SRC, ELoginSpec::SOURCE_PATH)
    module_eval(ELoginSpec::DELETE_LOGIN_ENTRY_SRC, ELoginSpec::SOURCE_PATH)
    module_eval(ELoginSpec::PARSE_ARGUMENTS_SRC, ELoginSpec::SOURCE_PATH)
  end
end

RSpec.describe 'ELogin (elogin.lic)' do
  # elogin.lic's Saga support only matters if it agrees with what the pinned
  # lich-5 release actually implements -- see ELoginSpec's own header
  # comment above. Skip everything here rather than fail a contributor who
  # hasn't cloned lich-5 locally.
  before do
    unless ELoginSpec::LICH5_PATH
      skip 'requires a local lich-5 checkout -- set LICH5_PATH, or clone lich-5 ' \
           'as a sibling ../lich-5 checkout (see spec_helper.rb#lich5_path)'
    end
  end

  before { ELoginSpec::Harness.reset! }

  let(:harness) { ELoginSpec::Harness }
  let(:calls) { harness.calls }

  def echoes
    calls.select { |c| c.first == :echo }.map { |c| c[1] }
  end

  def saved_entries
    calls.select { |c| c.first == :save }.map { |c| c[1] }
  end

  describe '.extract_frontend_flag' do
    it 'matches a bare frontend flag' do
      expect(harness.extract_frontend_flag(['--saga'])).to eq('saga')
    end

    it 'matches the long --frontend=NAME form' do
      expect(harness.extract_frontend_flag(['--frontend=saga'])).to eq('saga')
    end

    it 'is case-insensitive and downcases the result' do
      expect(harness.extract_frontend_flag(['--SAGA'])).to eq('saga')
    end

    it 'ignores unrelated flags' do
      expect(harness.extract_frontend_flag(['--GS3', '--custom-launch=warlock'])).to be_nil
    end

    it 'returns nil when no args are given' do
      expect(harness.extract_frontend_flag([])).to be_nil
    end
  end

  describe '.extract_custom_launch_flag' do
    it 'extracts the launcher value' do
      expect(harness.extract_custom_launch_flag(['--custom-launch=warlock'])).to eq('warlock')
    end

    it 'is case-insensitive on the flag name' do
      expect(harness.extract_custom_launch_flag(['--CUSTOM-LAUNCH=warlock'])).to eq('warlock')
    end

    it 'returns nil when absent' do
      expect(harness.extract_custom_launch_flag(['--saga'])).to be_nil
    end
  end

  describe '.parse_arguments' do
    it 'defaults to help on no args' do
      expect(harness.parse_arguments([])).to eq(command: :help)
    end

    it 'recognizes "help" case-insensitively' do
      expect(harness.parse_arguments(['HELP'])).to eq(command: :help)
    end

    it 'strips a redundant leading joined-args entry from Lich command processing' do
      result = harness.parse_arguments(['Char --saga', 'Char', '--saga'])

      expect(result).to include(command: :login, char_name: 'Char', frontend: 'saga')
    end

    describe '"set realm"' do
      it 'parses a valid realm, downcased' do
        expect(harness.parse_arguments(%w[set realm Prime])).to eq(command: :set_realm, realm: 'prime')
      end

      it 'falls back to help with no realm value' do
        expect(harness.parse_arguments(%w[set realm])).to eq(command: :help)
      end

      it 'falls back to help for an unknown subcommand' do
        expect(harness.parse_arguments(%w[set foo bar])).to eq(command: :help)
      end
    end

    describe '"add"' do
      it 'parses char/account/password with no extra flags' do
        result = harness.parse_arguments(%w[add Iaconelli MyAccount hunter2])

        expect(result).to eq(
          command: :add_entry, char_name: 'Iaconelli', user_id: 'myaccount',
          password: 'hunter2', frontend: nil, custom_launch: nil
        )
      end

      it 'allows the password to be omitted entirely' do
        result = harness.parse_arguments(%w[add Iaconelli MyAccount])

        expect(result).to include(password: nil)
      end

      it 'treats a leading flag as "no password", not a literal password' do
        result = harness.parse_arguments(['add', 'Iaconelli', 'MyAccount', '--frontend=saga'])

        expect(result).to include(password: nil, frontend: 'saga')
      end

      it 'still reads an explicit password ahead of trailing flags' do
        result = harness.parse_arguments(['add', 'Iaconelli', 'MyAccount', 'hunter2', '--frontend=saga'])

        expect(result).to include(password: 'hunter2', frontend: 'saga')
      end

      it 'extracts --custom-launch= alongside --frontend=' do
        result = harness.parse_arguments(['add', 'Iaconelli', 'MyAccount', '--custom-launch=warlock'])

        expect(result).to include(password: nil, custom_launch: 'warlock')
      end

      it 'falls back to help with fewer than char+account' do
        expect(harness.parse_arguments(%w[add Iaconelli])).to eq(command: :help)
      end
    end

    describe '"modify"' do
      it 'parses char/account/password with no extra flags' do
        result = harness.parse_arguments(%w[modify Iaconelli MyAccount newpass])

        expect(result).to eq(
          command: :modify_entry, char_name: 'Iaconelli', user_id: 'myaccount',
          password: 'newpass', frontend: nil, show_password: false
        )
      end

      it 'extracts --frontend= and --show-password' do
        result = harness.parse_arguments(
          ['modify', 'Iaconelli', 'MyAccount', 'newpass', '--frontend=saga', '--show-password']
        )

        expect(result).to include(frontend: 'saga', show_password: true)
      end

      it 'falls back to help with fewer than char+account+password' do
        expect(harness.parse_arguments(%w[modify Iaconelli MyAccount])).to eq(command: :help)
      end
    end

    it 'parses "list"' do
      expect(harness.parse_arguments(['list'])).to eq(command: :list_entries)
    end

    describe '"delete"' do
      it 'parses char/game_code with no frontend' do
        expect(harness.parse_arguments(%w[delete Iaconelli GS3]))
          .to eq(command: :delete_entry, char_name: 'Iaconelli', game_code: 'GS3', frontend: nil)
      end

      it 'accepts an optional frontend disambiguator' do
        expect(harness.parse_arguments(%w[delete Iaconelli GS3 saga]))
          .to eq(command: :delete_entry, char_name: 'Iaconelli', game_code: 'GS3', frontend: 'saga')
      end

      it 'accepts the disambiguator as a --frontend= flag, matching add/modify syntax' do
        expect(harness.parse_arguments(['delete', 'Iaconelli', 'GS3', '--frontend=saga']))
          .to eq(command: :delete_entry, char_name: 'Iaconelli', game_code: 'GS3', frontend: 'saga')
      end

      it 'accepts the disambiguator as a bare --saga flag' do
        expect(harness.parse_arguments(['delete', 'Iaconelli', 'GS3', '--saga']))
          .to eq(command: :delete_entry, char_name: 'Iaconelli', game_code: 'GS3', frontend: 'saga')
      end

      it 'falls back to help with fewer than char+game_code' do
        expect(harness.parse_arguments(%w[delete Iaconelli])).to eq(command: :help)
      end
    end

    describe 'login (default branch)' do
      it 'parses a bare character name' do
        result = harness.parse_arguments(['Iaconelli'])

        expect(result).to eq(
          command: :login, char_name: 'Iaconelli', instance_flag: :__unset,
          scripts: [], custom_launch: nil, frontend: nil
        )
      end

      it 'parses a trailing comma-separated script list' do
        result = harness.parse_arguments(['Iaconelli', 'script1,script2'])

        expect(result[:scripts]).to eq(%w[script1 script2])
      end

      it 'parses a bare --saga frontend flag' do
        result = harness.parse_arguments(['Iaconelli', '--saga'])

        expect(result[:frontend]).to eq('saga')
        expect(result[:scripts]).to eq([])
      end

      it 'parses the long --frontend=NAME form' do
        result = harness.parse_arguments(['Iaconelli', '--frontend=saga'])

        expect(result[:frontend]).to eq('saga')
      end

      it 'parses a game-instance override flag' do
        result = harness.parse_arguments(['Iaconelli', '--GS3'])

        expect(result[:instance_flag]).to eq('GS3')
      end

      it 'strips a lowercase instance flag from the script list instead of leaking it through' do
        result = harness.parse_arguments(['Iaconelli', '--gst'])

        expect(result[:instance_flag]).to eq('GST')
        expect(result[:scripts]).to eq([])
      end

      it 'parses --custom-launch=' do
        result = harness.parse_arguments(['Iaconelli', '--custom-launch=warlock'])

        expect(result[:custom_launch]).to eq('warlock')
      end

      it 'strips instance/frontend flags out before reading the script list' do
        result = harness.parse_arguments(['Iaconelli', '--GS3', '--saga', 'script1,script2'])

        expect(result).to include(instance_flag: 'GS3', frontend: 'saga', scripts: %w[script1 script2])
      end
    end
  end

  describe '.add_login_entry' do
    def entry(char_name:, game_code:, user_id:, frontend:, password: 'pw')
      { char_name: char_name, game_code: game_code, game_name: 'GemStone IV', user_id: user_id,
        password: password, frontend: frontend, custom_launch: nil, custom_launch_dir: nil }
    end

    it 'requires a password the first time an account is saved' do
      entry_data = []

      expect do
        harness.add_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'newaccount', password: nil,
                                             game_code: 'GS3', frontend: 'wrayth')
      end.to raise_error(ELoginSpec::ExitCalled)

      expect(echoes.last).to match(/password is required/i)
      expect(entry_data).to be_empty
      expect(saved_entries).to be_empty
    end

    it 'saves a brand new account with a password' do
      entry_data = []

      harness.add_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'MyAccount', password: 'hunter2',
                                           game_code: 'GS3', frontend: 'wrayth')

      expect(entry_data.length).to eq(1)
      expect(entry_data.first).to include(char_name: 'Iaconelli', user_id: 'myaccount',
                                          password: 'hunter2', frontend: 'wrayth')
      expect(saved_entries.length).to eq(1)
    end

    it 'allows omitting the password when adding another character to an already-saved account' do
      entry_data = [entry(char_name: 'Existing', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth')]

      harness.add_login_entry(entry_data, char_name: 'SecondChar', user_id: 'MyAccount', password: nil,
                                           game_code: 'GS3', frontend: 'wrayth')

      expect(entry_data.length).to eq(2)
      expect(entry_data.last).to include(char_name: 'SecondChar', user_id: 'myaccount', password: nil)
    end

    it 'refuses a duplicate character/game_code/frontend' do
      entry_data = [entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth')]

      expect do
        harness.add_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'pw',
                                             game_code: 'GS3', frontend: 'wrayth')
      end.to raise_error(ELoginSpec::ExitCalled)

      expect(echoes.last).to match(/already exists/i)
      expect(entry_data.length).to eq(1)
    end

    it 'allows a second entry for the same character/game_code under a different frontend' do
      entry_data = [entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth')]

      harness.add_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: nil,
                                           game_code: 'GS3', frontend: 'saga')

      expect(entry_data.length).to eq(2)
      expect(entry_data.map { |e| e[:frontend] }).to contain_exactly('wrayth', 'saga')
    end

    it 'refuses to save a Saga entry with a custom launch' do
      entry_data = []

      expect do
        harness.add_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'pw',
                                             game_code: 'GS3', frontend: 'saga', custom_launch: 'warlock')
      end.to raise_error(ELoginSpec::ExitCalled)

      expect(echoes.last).to match(/saga.*custom-launch/i)
      expect(entry_data).to be_empty
    end
  end

  describe '.modify_login_entry' do
    def entry(char_name:, game_code:, user_id:, frontend:, password:)
      { char_name: char_name, game_code: game_code, game_name: 'GemStone IV', user_id: user_id,
        password: password, frontend: frontend, custom_launch: nil, custom_launch_dir: nil }
    end

    it 'reports failure and exits when nothing matches' do
      entry_data = []

      expect do
        harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new')
      end.to raise_error(ELoginSpec::ExitCalled)

      expect(echoes).to include(match(/No entry found/))
    end

    it 'updates the password of the single matching entry, preserving other fields' do
      entry_data = [entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth',
                          password: 'old')]

      harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new')

      expect(entry_data.length).to eq(1)
      expect(entry_data.first).to include(password: 'new', game_code: 'GS3', frontend: 'wrayth')
    end

    it 'exits without changing anything when the char/account is ambiguous and no frontend is given' do
      wrayth = entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth',
                     password: 'wrayth-pw')
      saga = entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'saga',
                   password: 'saga-pw')
      entry_data = [wrayth, saga]

      expect do
        harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new')
      end.to raise_error(ELoginSpec::ExitCalled)

      expect(echoes.last).to match(/Multiple entries exist/)
      expect(entry_data).to eq([wrayth, saga])
    end

    it 'uses the given frontend only to validate which entry to act on, not to scope the password update' do
      wrayth = entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth',
                     password: 'wrayth-pw')
      saga = entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'saga',
                   password: 'saga-pw')
      entry_data = [wrayth, saga]

      harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new-pw',
                                              frontend: 'saga')

      # Same objects, in place -- not replaced/reordered.
      expect(entry_data).to eq([wrayth, saga])
      # The account's password is one value shared by every entry under it,
      # so both get the update, not just the one the frontend identified.
      expect(entry_data.map { |e| e[:password] }).to eq(%w[new-pw new-pw])
      expect(wrayth[:frontend]).to eq('wrayth')
      expect(saga[:frontend]).to eq('saga')
    end

    it 'updates every saved entry for the account, even ones for a different character' do
      iaconelli = entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth',
                        password: 'old')
      second_char = entry(char_name: 'Secondchar', game_code: 'DR', user_id: 'myaccount', frontend: 'wrayth',
                          password: 'old')
      entry_data = [iaconelli, second_char]

      harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new')

      expect(entry_data.map { |e| e[:password] }).to eq(%w[new new])
    end

    it 'exits when the given frontend matches none of the ambiguous entries' do
      wrayth = entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth',
                     password: 'wrayth-pw')
      saga = entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'saga',
                   password: 'saga-pw')
      entry_data = [wrayth, saga]

      expect do
        harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new',
                                                frontend: 'avalon')
      end.to raise_error(ELoginSpec::ExitCalled)

      expect(entry_data).to eq([wrayth, saga])
    end

    context 'with debug messaging enabled' do
      before { harness.debug_messaging = true }

      it 'never lets the debug log see the plaintext password' do
        entry_data = [entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth',
                            password: 'super-secret')]

        harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new')

        debug_messages = calls.select { |c| c.first == :messaging && c[1] == 'debug' }.map { |c| c[2] }
        expect(debug_messages).not_to be_empty # sanity: debug logging actually ran
        expect(debug_messages.none? { |msg| msg.include?('super-secret') }).to be true
        expect(debug_messages.none? { |msg| msg.include?('new') }).to be true
      end
    end

    context 'with show_password: true' do
      it 'pauses before revealing the old password, and only echoes it after' do
        entry_data = [entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth',
                            password: 'super-secret')]

        harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new',
                                                show_password: true)

        pause_index = calls.index { |c| c.first == :pause }
        reveal_index = calls.index { |c| c.first == :echo && c[1].include?('super-secret') }

        expect(pause_index).not_to be_nil
        expect(reveal_index).not_to be_nil
        expect(pause_index).to be < reveal_index
      end

      it 'reveals the old password, not the new one being saved' do
        entry_data = [entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth',
                            password: 'old-secret')]

        harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new-secret',
                                                show_password: true)

        expect(echoes).to include(match(/old-secret/))
        expect(echoes.none? { |e| e.include?('new-secret') }).to be true
      end
    end

    context 'without show_password' do
      it 'never pauses the script' do
        entry_data = [entry(char_name: 'Iaconelli', game_code: 'GS3', user_id: 'myaccount', frontend: 'wrayth',
                            password: 'old')]

        harness.modify_login_entry(entry_data, char_name: 'Iaconelli', user_id: 'myaccount', password: 'new')

        expect(calls.none? { |c| c.first == :pause }).to be true
      end
    end
  end

  describe '.delete_login_entry' do
    def entry(char_name:, game_code:, frontend:)
      { char_name: char_name, game_code: game_code, game_name: 'GemStone IV', user_id: 'myaccount',
        password: 'pw', frontend: frontend, custom_launch: nil, custom_launch_dir: nil }
    end

    it 'returns false and does not save when nothing matches' do
      entry_data = []

      result = harness.delete_login_entry(entry_data, char_name: 'Iaconelli', game_code: 'GS3')

      expect(result).to be false
      expect(saved_entries).to be_empty
    end

    it 'deletes the single matching entry when no frontend is given' do
      entry_data = [entry(char_name: 'Iaconelli', game_code: 'GS3', frontend: 'wrayth')]

      result = harness.delete_login_entry(entry_data, char_name: 'Iaconelli', game_code: 'GS3')

      expect(result).to be true
      expect(entry_data).to be_empty
      expect(saved_entries.length).to eq(1)
    end

    it 'does NOT delete or report success when the single matching entry has a different frontend' do
      entry_data = [entry(char_name: 'Iaconelli', game_code: 'GS3', frontend: 'wrayth')]

      result = harness.delete_login_entry(entry_data, char_name: 'Iaconelli', game_code: 'GS3', frontend: 'saga')

      expect(result).to be false
      expect(entry_data.length).to eq(1)
      expect(saved_entries).to be_empty
    end

    it 'requires a frontend to disambiguate multiple matches, and reports failure without saving' do
      wrayth = entry(char_name: 'Iaconelli', game_code: 'GS3', frontend: 'wrayth')
      saga = entry(char_name: 'Iaconelli', game_code: 'GS3', frontend: 'saga')
      entry_data = [wrayth, saga]

      result = harness.delete_login_entry(entry_data, char_name: 'Iaconelli', game_code: 'GS3')

      expect(result).to be false
      expect(entry_data).to eq([wrayth, saga])
      expect(saved_entries).to be_empty
    end

    it 'deletes only the entry matching the given frontend, leaving its sibling untouched' do
      wrayth = entry(char_name: 'Iaconelli', game_code: 'GS3', frontend: 'wrayth')
      saga = entry(char_name: 'Iaconelli', game_code: 'GS3', frontend: 'saga')
      entry_data = [wrayth, saga]

      result = harness.delete_login_entry(entry_data, char_name: 'Iaconelli', game_code: 'GS3', frontend: 'saga')

      expect(result).to be true
      expect(entry_data).to eq([wrayth])
    end
  end

  # The Saga preflight check and the login spawn logic live inline in .run's
  # case statement rather than in an independently callable method, and .run
  # also reaches for Lich-runtime pieces (Process.spawn, RbConfig, OS, the
  # full LoginHelpers matching API) far beyond what's worth re-stubbing here.
  # These are pinned structurally against the shipped source instead, the
  # same way eloot.lic's non-extractable routing is pinned in its own specs.
  describe '.run (Saga preflight, structural)' do
    let(:run_body) { ELoginSpec::RUN_SRC }

    it 'only checks for a saga-tagged entry when saga was actually requested' do
      expect(run_body).to match(/if frontend_override\.to_s\.casecmp\?\('saga'\)/)
    end

    it 'requires an entry tagged frontend: saga for the exact character/instance' do
      expect(run_body).to match(/d\[:frontend\]\.to_s\.casecmp\?\('saga'\)/)
      expect(run_body).to match(/d\[:game_code\]\.to_s\.casecmp\?\(login_game_code\)/)
    end

    it "tells the player how to fix it, without asking for a password they don't need" do
      # Single-quoted deliberately: a literal substring match against the source
      # text, not interpolation -- char_entry does not exist in this spec.
      expect(run_body).to include('add #{char_entry[:char_name]} #{char_entry[:user_id]} --frontend=saga') # rubocop:disable Lint/InterpolationCheck
      expect(run_body).to match(/no password needed/i)
    end

    it 'reports the missing-entry error via handle_error rather than spawning anyway' do
      guard = run_body.index(/unless saga_entry_exists/)
      spawn = run_body.index(/Process\.spawn/)

      expect(guard).not_to be_nil
      expect(spawn).not_to be_nil
      expect(guard).to be < spawn
    end
  end

  # select_best_fit's frontend-scoring tie-break (see login_helpers.rb) only
  # kicks in when it's told what frontend was requested; omitting it let a
  # sibling entry's stored :custom_launch leak into an unrelated login (e.g.
  # forcing a false Saga/custom-launch conflict for a character that also has
  # an old custom-launch entry under a different frontend). Pinned
  # structurally alongside the rest of .run's non-extractable logic.
  describe '.run select_best_fit frontend resolution (structural)' do
    let(:run_body) { ELoginSpec::RUN_SRC }

    it 'tells select_best_fit which frontend was requested instead of leaving it unset' do
      expect(run_body).to match(/select_best_fit\(/)
      select_best_fit_call = run_body[/select_best_fit\(\n[\s\S]*?\n\s*\)/]
      expect(select_best_fit_call).not_to be_nil
      expect(select_best_fit_call).to match(/requested_fe:\s*parsed\[:frontend\]\s*\|\|\s*:__unset/)
    end
  end

  # The debug-only accounts lookup in load_yaml_entries used to run
  # unconditionally, including on a nil/non-Hash `accounts` key, which raised
  # a NoMethodError that masked the real entry.yaml parse error. Pinned
  # structurally since load_yaml_entries itself needs the full
  # EntryStore/YAML stack to execute.
  describe '.load_yaml_entries accounts guard (structural)' do
    let(:load_yaml_entries_body) { ELoginSpec::LOAD_YAML_ENTRIES_SRC }

    it 'only calls .count on accounts once it is confirmed to respond to it' do
      expect(load_yaml_entries_body).to match(/accounts\.respond_to\?\(:count\)/)
    end

    it 'guards the accounts lookup itself against a non-Hash raw_yaml' do
      expect(load_yaml_entries_body).to match(/raw_yaml\.is_a\?\(Hash\)\s*\?\s*raw_yaml\['accounts'\]\s*:\s*nil/)
    end
  end
end
