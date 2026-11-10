require 'tmpdir'
require 'fileutils'
require 'ostruct'
require 'timeout'
require_relative 'lich_script_vars'

# The harness log_spec.rb and log_xml_mode_spec.rb run log.lic in
# (log_xml_mode_spec.rb runs the whole script, see run_whole_script).
#
# Stand-ins for the parts of lich-5 that log.lic's `module GameLogger` uses,
# kept off the top level: the module is evaluated inside
# LogSpecHarness::Env (see evaluate_game_logger), so its bare XMLData,
# Script and Lich resolve to the stubs nested there, and Lich's script
# helpers (get, echo, reget, upstream_get, get_settings, hide_me) come from
# ScriptHelpers, which GameLogger and Env extend. Nothing here reopens a top-level constant or defines
# a top-level method, so other spec files keep their own (spec_helper.rb
# asks for this). The game globals log.lic reads ($login_time) are set per
# example and put back after.
module LogSpecHarness
  # Script.current.downstream_buffer: what `get` reads, and where the
  # logger's upstream thread pushes its ">command" lines.
  DOWNSTREAM = Thread::Queue.new
  # The commands an example "typed", for upstream_get.
  UPSTREAM = Thread::Queue.new

  class << self
    # Seconds `get` waits for a line before it raises StopIteration.
    attr_accessor :idle_timeout
    # What get_settings answers: lich-5 always defines it
    # (lib/global_defs.rb), in GemStone too, where a character with no
    # yaml gets an empty OpenStruct.
    attr_accessor :settings
    # The thread the last GameLogger::Logger.start_upstream_logger call started
    # (see UpstreamTracker), for wait_for_upstream!.
    attr_accessor :upstream_thread
    # How many times the script called hide_me.
    attr_reader :hide_me_calls
    # $_SERVERBUFFER_ as reget reads it: the raw lines the server sent,
    # XML tags and "\r" line ends included.
    attr_accessor :server_buffer
    # The current run's Script.current (see new_script).
    attr_reader :script, :echoes
    # The scripts running besides the current run, for Script.running and
    # Script.hidden: OpenStructs with a name and hidden ([] after reset!).
    attr_accessor :other_scripts

    # Puts the harness back to a fresh start for the next example: empty
    # buffers, no echoes, no settings, no server buffer, no upstream
    # thread, no other running scripts, and a new Script.current with no
    # arguments.
    #
    # @return [OpenStruct] the new Script.current (see {new_script})
    def reset!
      DOWNSTREAM.clear
      UPSTREAM.clear
      @echoes = []
      @idle_timeout = 0
      @wait_for_upstream = false
      @upstream_thread = nil
      @hide_me_calls = 0
      @settings = OpenStruct.new
      @server_buffer = []
      @other_scripts = []
      @script = new_script
    end

    # Lich's hide_me: counts the call (see {hide_me_calls}).
    #
    # @return [nil]
    def hide_me
      @hide_me_calls += 1
      nil
    end

    # Makes `get` end the run once the logger's upstream thread has ended
    # and the buffer is empty, so the ">command" lines and notices it
    # pushed are read first. A thread still running after two seconds
    # fails the example instead of ending it.
    #
    # @return [Integer] the new idle_timeout, 2
    def wait_for_upstream!
      @wait_for_upstream = true
      @idle_timeout = 2
    end

    # A Script.current with lich-5's defaults (lib/common/script.rb,
    # Script#initialize): text downstream on, XML downstream, script output
    # and upstream off, and vars built from +args+ as lich-5 builds them.
    #
    # @param args [String, Array<String>, nil] a String as typed (;log ...),
    #   an Array as autostart passes its saved arguments, nil for none
    # @param name [String] the script's name, Script.current.name ('log',
    #   or 'logxml' for a run an install's local logxml.lic starts, which
    #   picks XML mode)
    # @return [OpenStruct] the stand-in Script, with +downstream_buffer+
    #   set to {DOWNSTREAM}
    def new_script(args = nil, name: 'log')
      OpenStruct.new(
        name: name,
        vars: script_vars(args),
        want_downstream: true,
        want_downstream_xml: false,
        want_script_output: false,
        want_upstream: false,
        downstream_buffer: DOWNSTREAM
      )
    end

    # Starts the next run as lich-5 starts a script with these arguments.
    #
    # @param args [String, Array<String>, nil] the arguments, as for
    #   {new_script}
    # @param name [String] the script's name, as for {new_script}
    # @return [OpenStruct] the new Script.current
    def start_script(args, name: 'log')
      @script = new_script(args, name: name)
    end

    # lich-5's Script#initialize vars (see LichScriptVars.build).
    #
    # @param args [String, Array<String>, nil] the arguments, as for
    #   {new_script}
    # @return [Array<String>] the vars: the whole argument string, then
    #   each argument; [] for none
    def script_vars(args)
      LichScriptVars.build(args)
    end

    # Queues game lines for `get` to hand the logger, in order. Strings are
    # copied, so a frozen literal reaches the logger unfrozen, as Lich's
    # lines do; anything else is queued as is.
    #
    # @param lines [Array<String, Object>] the lines; nested Arrays are
    #   flattened
    # @return [Array] the flattened lines
    def feed(*lines)
      lines.flatten.each { |line| DOWNSTREAM << (line.is_a?(String) ? line.dup : line) }
    end

    # Queues commands as if typed, for `upstream_get` to hand the logger's
    # upstream thread, in order.
    #
    # @param commands [Array<String>] the commands; nested Arrays are
    #   flattened
    # @return [Array<String>] the flattened commands
    def type(*commands)
      commands.flatten.each { |command| UPSTREAM << command.dup }
    end

    # lich-5's get pops the downstream buffer and blocks while it is
    # empty; here it raises StopIteration after idle_timeout instead, which
    # ends GameLogger.main's `loop` (see wait_for_upstream! for the runs
    # that wait for typed commands).
    #
    # @return [String, Object] the next queued line
    # @raise [StopIteration] when no line comes within idle_timeout (or,
    #   after {wait_for_upstream!}, once the upstream thread has ended and
    #   the buffer is empty)
    def get
      return wait_for_line_or_upstream_end if @wait_for_upstream

      line = DOWNSTREAM.pop(timeout: idle_timeout)
      raise StopIteration if line.nil?

      line
    end

    # `get` after {wait_for_upstream!}: waits for the next line until the
    # upstream thread has ended with the buffer empty.
    #
    # @return [String, Object] the next queued line
    # @raise [StopIteration] once the upstream thread has ended and the
    #   buffer is empty
    # @raise [RuntimeError] when the upstream thread is still running after
    #   idle_timeout seconds
    def wait_for_line_or_upstream_end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + idle_timeout
      # Not Kernel#loop, which would swallow the StopIteration.
      until (line = DOWNSTREAM.pop(timeout: 0.01))
        # alive? first: once the thread has ended, everything it pushed is
        # in the buffer.
        thread = upstream_thread
        raise StopIteration if thread && !thread.alive? && DOWNSTREAM.empty?
        raise "the upstream thread was still running after #{idle_timeout} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      end
      line
    end

    # Lich's upstream_get: the next typed command. Lich's blocks while
    # there is none; this raises StopIteration, which ends the logger's
    # upstream loop.
    #
    # @return [String] the next command queued with {type}
    # @raise [StopIteration] when no command is queued
    def upstream_get
      UPSTREAM.pop(true)
    rescue ThreadError
      raise StopIteration
    end

    # Lich's echo: keeps the message in {echoes}.
    #
    # @param msg [Object] the message, kept as its to_s
    # @return [Array<String>] every echo of the run so far
    def echo(msg)
      @echoes << msg.to_s
    end

    # lich-5's reget with no arguments (lib/global_defs.rb:1601-1633): the
    # server buffer joined on "\n"; unless the script wants the XML
    # downstream, the stream/tag blocks are cut, every tag removed and
    # &gt; &lt; decoded; split on "\n" with blank lines dropped (a "\r" left
    # at each line end stays); nil, never [], when nothing is left.
    #
    # @return [Array<String>, nil] the reget lines, or nil when none are
    #   left
    def reget
      history = server_buffer.join("\n")
      unless script.want_downstream_xml
        history = history.gsub(%r{<pushStream id=["'](?:spellfront|inv|bounty|society)["'][^>]*/>.*?<popStream[^>]*>}m, '')
        history = history.gsub(%r{<stream id="Spells">.*?</stream>}m, '')
        history = history.gsub(%r{<(compDef|inv|component|right|left|spell|prompt)[^>]*>.*?</\1>}m, '')
        history = history.gsub(/<[^>]+>/, '').gsub('&gt;', '>').gsub('&lt;', '<')
      end
      lines = history.split("\n").reject { |line| line.empty? || line =~ /^[\r\n\s\t]*$/ }
      lines.empty? ? nil : lines
    end
  end

  # The namespace log.lic's module is evaluated in, holding the constants
  # it reads by bare name.
  module Env
    # Lich's XMLData, with one fixed GemStone character and room.
    module XMLData
      # @return [String] the game code, "GSIV"
      def self.game = "GSIV"
      # @return [String] the character's name, "TestChar"
      def self.name = "TestChar"
      # @return [Integer] the room's game UID, 1234
      def self.room_id = 1234
      # @return [String] the room title, "[Town Square]"
      def self.room_title = "[Town Square]"
      # @return [Integer] the room counter, 0
      def self.room_count = 0
    end

    # Lich, for Lich.log only.
    module Lich
      # Lich.log: drops the message (examples that check it stub it).
      #
      # @param _msg [String] the message
      # @return [nil]
      def self.log(_msg); end
    end

    # Lich's Script, for Script.current, Script.running and Script.hidden.
    class Script
      # @return [OpenStruct] the current run's script (see
      #   {LogSpecHarness.new_script})
      def self.current = LogSpecHarness.script

      # lich-5's Script.running: the running scripts that are not hidden.
      #
      # @return [Array<OpenStruct>] the {LogSpecHarness.other_scripts} not
      #   hidden (the current run has called hide_me)
      def self.running = LogSpecHarness.other_scripts.reject(&:hidden)

      # lich-5's Script.hidden: the running scripts that are hidden.
      #
      # @return [Array<OpenStruct>] the current run, then the
      #   {LogSpecHarness.other_scripts} that are hidden
      def self.hidden = [LogSpecHarness.script, *LogSpecHarness.other_scripts.select(&:hidden)]
    end
  end

  # Lich's global script helpers, which log.lic calls with no receiver.
  # GameLogger extends this module, so they win over any top-level method
  # of the same name another spec file defines.
  module ScriptHelpers
    private

    # @return [String, Object] the next game line (see {LogSpecHarness.get})
    def get = LogSpecHarness.get
    # @return [String] the next typed command (see
    #   {LogSpecHarness.upstream_get})
    def upstream_get = LogSpecHarness.upstream_get
    # @param msg [Object] the message (see {LogSpecHarness.echo})
    # @return [Array<String>] every echo of the run so far
    def echo(msg) = LogSpecHarness.echo(msg)
    # @return [Array<String>, nil] the reget lines (see
    #   {LogSpecHarness.reget})
    def reget = LogSpecHarness.reget
    # @return [OpenStruct] the character's settings (see
    #   {LogSpecHarness.settings})
    def get_settings = LogSpecHarness.settings
    # @return [nil] nothing, after counting the call ({LogSpecHarness.hide_me})
    def hide_me = LogSpecHarness.hide_me
  end

  # Prepended to each GameLogger::Logger's singleton class (see
  # LoggerHook): keeps the thread start_upstream_logger starts (Logger#run
  # drops it), so a run can wait for it to end.
  module UpstreamTracker
    # Starts the upstream thread as the Logger does and keeps it in
    # {LogSpecHarness.upstream_thread}.
    #
    # @return [Thread] the upstream thread
    def start_upstream_logger
      LogSpecHarness.upstream_thread = super
    end
  end

  # Extended onto GameLogger before log.lic is first evaluated. Every
  # evaluation sets a new GameLogger::Logger class, whose own methods call
  # Lich's script helpers (echo, upstream_get) with no receiver; each one
  # gets ScriptHelpers and UpstreamTracker as it is set, also when the
  # whole script runs (run_whole_script), which starts the run at once.
  module LoggerHook
    # Ruby's hook for a constant set on GameLogger: when it is Logger, the
    # new class gets ScriptHelpers and UpstreamTracker.
    #
    # @param name [Symbol] the constant's name
    # @return [void]
    def const_added(name)
      super
      return unless name == :Logger

      logger = const_get(name, false)
      logger.extend(ScriptHelpers)
      logger.singleton_class.prepend(UpstreamTracker)
    end
  end

  reset!
end

script_path = File.join(__dir__, '..', '..', 'scripts', 'log.lic')
script_content = File.read(script_path)
module_code = script_content[/^module GameLogger.*?^end/m]
raise "Failed to extract GameLogger module from #{script_path}" if module_code.nil?
raise "Extracted code does not look like a single module" unless module_code.scan(/^module GameLogger/).one?

module_line = script_content.lines.index { |l| l.start_with?('module GameLogger') } + 1

# Lich evaluates log.lic from its first line, so its magic comment
# (frozen_string_literal) applies to every literal in the module and the
# script body. Each extracted piece gets the same comment on a line of its
# own, one line above where it starts, so literals are frozen here as they
# are in Lich and backtraces still give log.lic's line numbers.
magic_comment = script_content.lines.first[/\A#\s*frozen_string_literal:\s*\w+\s*\n/].to_s
magic_lines = magic_comment.empty? ? 0 : 1
module_code = magic_comment + module_code
module_line -= magic_lines

# Evaluates log.lic's `module GameLogger` body in LogSpecHarness::Env, as
# Lich does each time the script starts: every run of log.lic in a session
# evaluates the module again in the same namespace, while earlier runs may
# still be logging.
LogSpecHarness.define_singleton_method(:evaluate_game_logger) do
  LogSpecHarness::Env.module_eval(module_code, script_path, module_line)
end
# GameLogger exists before log.lic is evaluated, so its module body reopens
# this one, which has the script helpers and LoggerHook from the start.
module LogSpecHarness::Env
  # log.lic's GameLogger, made here first; evaluating log.lic reopens it.
  module GameLogger
    extend LogSpecHarness::ScriptHelpers
    extend LogSpecHarness::LoggerHook
  end
end
LogSpecHarness.evaluate_game_logger

# Everything after the =end header (hide_me, the module and the
# GameLogger.main call), as Lich runs the script. It runs in Env, whose
# calls with no receiver (hide_me) go to ScriptHelpers; the line number
# keeps backtraces pointing at log.lic.
script_body_line = script_content.lines.index { |l| l.start_with?('=end') } + 2
script_body = magic_comment + script_content.lines.drop(script_body_line - 1).join
script_body_line -= magic_lines
LogSpecHarness::Env.extend(LogSpecHarness::ScriptHelpers)
LogSpecHarness.define_singleton_method(:run_whole_script) do
  LogSpecHarness::Env.module_eval(script_body, script_path, script_body_line)
end
