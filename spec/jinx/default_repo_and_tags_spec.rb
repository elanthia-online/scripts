require 'tmpdir'
require "rack"
require 'webmock'

# Mock XMLData
module XMLData
  def self.game
    "GSIV"
  end
end

load "scripts/jinx.lic"

$fake_game_output = ""

def _respond(*args)
  $fake_game_output = $fake_game_output + "\n" + args.join("\n")
end

def respond(*args)
  $fake_game_output = $fake_game_output + "\n" + args.join("\n")
end

def game_output
  buffered = $fake_game_output.dup
  $fake_game_output = ""
  return buffered
end

module ::Lich
  module Common
    module Jinx
      describe "default repo and tag search" do
        unless ENV['ENABLE_EXTERNAL_NETWORKING'] && !%w[false no n 0].include?(ENV['ENABLE_EXTERNAL_NETWORKING'].downcase)
          before(:all) do
            WebMock.enable!
            {
              'extras'          => 'extras.repo.elanthia.online',
              'archive'         => 'archive.lich.elanthia.online',
              'mirror'          => 'ffnglichrepoarchive.netlify.app',
              'mapdb-backup-gs' => 'elanthia-online.github.io/mapdb-backup-gs',
            }.each do |(dir, domain)|
              WebMock.stub_request(:any, %r{https://#{domain}})
                     .to_rack(Rack::Directory.new(File.join(__dir__, 'repos', dir)))
            end
          end

          after(:all) do
            WebMock.disable!
          end
        end

        before(:each) do
          $data_dir = Dir.mktmpdir("data")
          $script_dir = Dir.mktmpdir("scripts")
          $lich_dir = Dir.mktmpdir("lich")
          Setup.apply
          game_output
        end

        describe "tag search" do
          # "alterations" is a tag of alter.lic only and no file name matches
          # ^alterations$, so a hit proves the match came from the tag
          it "script search finds a script by a tag that is not in its name" do
            Service.run("script search ^alterations$")
            output = game_output
            expect(output).to include("found 1 match")
            expect(output).to include("alter.lic")
            expect(output).to match(/\[tags: [^\]]*alterations/)
          end

          it "search finds a script by tag" do
            Service.run("search movement")
            output = game_output
            expect(output).to include("go2.lic")
            expect(output).to include("tags: core, movement")
          end

          it "still finds scripts by name" do
            Service.run("script search ^go2")
            output = game_output
            expect(output).to include("found 1 match")
            expect(output).to include("go2.lic")
          end

          it "treats command words as search terms" do
            # these words used to be read as --repo, or as other subcommands
            expect { Service.run("search repo") }.not_to raise_error
            expect(game_output).to include("jinx.lic")
            Service.run("script search list")
            expect(game_output).to match(/found \d+ match/)
          end

          it "matches tags and names regardless of case, like the GUI filter" do
            Service.run("search MOVEMENT")
            expect(game_output).to include("go2.lic")
            Service.run("script search ^GO2")
            output = game_output
            expect(output).to include("found 1 match")
            expect(output).to include("go2.lic")
          end

          it "matches nothing when neither the name nor a tag matches" do
            Service.run("script search zzzznotatagzzzz")
            expect(game_output).to include("found 0 matches")
          end
        end

        describe "gui" do
          it "tells an older Lich to update when the WebUI is missing" do
            expect(defined?(::Lich::API)).to be_nil
            expect { Service.run("gui") }.not_to raise_error
            output = game_output
            expect(output).to include("jinx gui needs Lich 5.26.0 or later")
            expect(output).to include("Please update Lich")
          end

          it "marks the gui command in help as needing Lich 5.26.0 on an older Lich" do
            Service.run("help")
            expect(game_output).to include("launch graphical interface (needs Lich 5.26.0+)")
          end

          it "says --no-gui, not update, when the WebUI is loaded but has no window" do
            api = Module.new { def self.webui_page(**) = raise("must not register a page") }
            webui = Module.new { def self.presentation_enabled? = false }
            stub_const("::Lich::API", api)
            stub_const("::Lich::WebUI", webui)
            expect { Service.run("gui") }.not_to raise_error
            output = game_output
            expect(output).to include("jinx gui has no window while Lich runs with --no-gui")
            expect(output).not_to include("update Lich")
          end

          it "passes non-UTF-8 text from a repo header to the window as valid UTF-8" do
            GUI.instance_variable_set(:@log, [])
            # a curly apostrophe (UTF-8 bytes) and a stray Latin-1 byte, as Net::HTTP returns them
            apostrophe = [0x2019].pack("U")
            header = "for when you#{apostrophe}re away ".b + [0xE9].pack("C")
            captured = GUI.capture_output { GUI.mono(header) }
            expect(captured.map(&:encoding).uniq).to eq([Encoding::UTF_8])
            expect(captured.all?(&:valid_encoding?)).to be(true)
            expect(captured.first).to include("you#{apostrophe}re away ?")
            GUI.append_log(header)
            expect(GUI.instance_variable_get(:@log).last).to be_valid_encoding
          end

          it "keeps routing output into the open window after jinx.lic is reloaded" do
            # every ;jinx run reloads the file; output routing must survive that
            load "scripts/jinx.lic"
            GUI.instance_variable_set(:@log, [])
            GUI.instance_variable_set(:@alive, true)
            GUI.instance_variable_set(:@script_thread, Thread.current)
            captured = GUI.capture_output { Log.mono("<b>go2.lic</b> (repo: elanthia-online)") }
            expect(captured).to eq(["go2.lic (repo: elanthia-online)"])
            Log.mono("installed &lt;go2&gt;")
            expect(GUI.instance_variable_get(:@log)).to eq(["installed <go2>"])
            expect(game_output).not_to include("go2")
          ensure
            GUI.instance_variable_set(:@alive, false)
            GUI.instance_variable_set(:@script_thread, nil)
          end

          it "prints a ;force jinx run's output in the game while another run owns the window" do
            owner = Thread.new { sleep }
            GUI.instance_variable_set(:@log, [])
            GUI.instance_variable_set(:@alive, true)
            GUI.instance_variable_set(:@script_thread, owner)
            Log.mono("found 3 matches")
            expect(game_output).to include("found 3 matches")
            expect(GUI.instance_variable_get(:@log)).to eq([])
          ensure
            owner&.kill
            GUI.instance_variable_set(:@alive, false)
            GUI.instance_variable_set(:@script_thread, nil)
          end

          describe "asset actions" do
            def gui_row(file, tags = [])
              { key: "elanthia-online/#{file}", file: file, repo: "elanthia-online", tags: tags }
            end

            before(:each) do
              GUI.reset_state!
              rows = [gui_row("bar.lic"), gui_row("foo.lic")]
              GUI.instance_variable_set(:@assets, { script: rows, data: [] })
              GUI.instance_variable_set(:@asset_index, { script: rows.to_h { |r| [r[:key], r] }, data: {} })
              allow(GUI).to receive(:rebuild_assets)
              GUI.perform(:select, :script, ["elanthia-online/foo.lic"])
            end

            it "does not install a selected row that the search has hidden" do
              expect(CLI).not_to receive(:script_install)
              GUI.perform(:filter, :script, "bar")
              GUI.perform(:install, :script, true)
              expect(GUI.instance_variable_get(:@log).last).to include("Select a script in the table first")
            end

            it "acts on the selection again once the filter is cleared" do
              GUI.perform(:filter, :script, "bar")
              GUI.perform(:clear_filter, :script)
              expect(CLI).to receive(:script_install).with("foo.lic", "elanthia-online", force: false)
              GUI.perform(:install, :script, false)
            end

            it "gives the search box a new key on Clear even when no filter was applied" do
              expect { GUI.perform(:clear_filter, :script) }
                .to change { GUI.instance_variable_get(:@input_generation)[:script] }.by(1)
            end

            it "keeps the search box key when an empty search is submitted with no filter applied" do
              expect { GUI.perform(:filter, :script, "") }
                .not_to(change { GUI.instance_variable_get(:@input_generation)[:script] })
            end
          end

          describe "a second ;force jinx gui while a window is open" do
            let(:owner) { Thread.new { sleep } }

            after(:each) do
              owner.kill
              GUI.instance_variable_set(:@alive, false)
              GUI.instance_variable_set(:@script_thread, nil)
              GUI.instance_variable_set(:@page, nil)
            end

            it "is refused and leaves the open window's state alone" do
              GUI.reset_state!
              page = Object.new
              commands = GUI.instance_variable_get(:@commands)
              GUI.instance_variable_set(:@alive, true)
              GUI.instance_variable_set(:@script_thread, owner)
              GUI.instance_variable_set(:@page, page)

              load "scripts/jinx.lic" # every ;jinx run re-evaluates the file
              expect(GUI.alive?).to be(true)

              GUI.start!
              expect(game_output).to include("already open; close that window first")
              expect(GUI.alive?).to be(true)
              expect(GUI.instance_variable_get(:@page)).to equal(page)
              expect(GUI.instance_variable_get(:@script_thread)).to equal(owner)
              expect(GUI.instance_variable_get(:@commands)).to equal(commands)
            end
          end
        end

        describe "repo default" do
          it "reports when no default is set" do
            Service.run("repo default")
            expect(game_output).to include("no default repo set")
          end

          it "sets, shows, and clears the default" do
            Service.run("repo default mirror")
            expect(game_output).to include("default repo set to mirror")
            expect(Repo.default_name).to eq(:mirror)

            Service.run("repo default")
            expect(game_output).to include("default repo: mirror")

            Service.run("repo list")
            output = game_output
            expect(output).to include("mirror:</b> (default)")
            expect(output).to include("elanthia-online:</b>\n")

            Service.run("repo default --clear")
            expect(game_output).to include("default repo cleared")
            expect(Repo.default_name).to be_nil
          end

          it "is not stored as a repo" do
            Service.run("repo default mirror")
            expect(Repo.map { |repo| repo[:name] }).to contain_exactly(:"elanthia-online", :mirror, :"mapdb-backup-gs")
          end

          it "refuses an unknown repo" do
            expect { Service.run("repo default nope") }
              .to raise_error(Jinx::Error, /repo\(nope\) is not known/)
            expect(Repo.default_name).to be_nil
          end

          it "scopes search to the default unless --all or --repo is given" do
            Service.run("repo default mirror")
            game_output

            Service.run("script search go2")
            output = game_output
            expect(output).to include("found 0 matches")
            expect(output).to include("add --all to search every repo")

            Service.run("script search go2 --all")
            output = game_output
            expect(output).to include("found 1 match")
            expect(output).to include("elanthia-online>")

            Service.run("script search go2 --repo=elanthia-online")
            expect(game_output).to include("found 1 match")

            Service.run("search loot")
            output = game_output
            expect(output).to include("sloot.lic")
            expect(output).not_to include("elanthia-online>")
          end

          it "scopes install to the default and points at --all when the asset is elsewhere" do
            Service.run("repo default mirror")
            game_output

            expect { Service.run("script install go2") }
              .to raise_error(Jinx::Error, /your default repo; add --all/)
            expect { Service.run("install go2") }
              .to raise_error(Jinx::Error, /your default repo; add --all/)

            Service.run("install go2 --all")
            expect(File.exist?(File.join($script_dir, "go2.lic"))).to be true
          end

          it "lets a default repo settle which copy of a duplicated asset to use" do
            Service.run("repo add archive https://archive.lich.elanthia.online")
            expect { Service.run("script info noop") }
              .to raise_error(Jinx::Error, /more than one repo has asset/)
            Service.run("repo default archive")
            game_output
            Service.run("script info noop")
            expect(game_output).to include("noop (repo: archive, modified:")
          end

          it "refuses --repo together with --all" do
            expect { Service.run("script search go2 --repo=mirror --all") }
              .to raise_error(Jinx::Error, /--repo and --all cannot be used together/)
          end

          it "refuses --repo without a name" do
            expect { Service.run("script search go2 --repo") }
              .to raise_error(Jinx::Error, /--repo needs exactly one repo name/)
          end

          it "clears the default when that repo is removed" do
            Service.run("repo default mirror")
            game_output
            Service.run("repo rm mirror")
            expect(game_output).to include("default has been cleared")
            expect(Repo.default_name).to be_nil
            expect(Settings.get(:default_repo)).to be_nil
          end
        end
      end
    end
  end
end
