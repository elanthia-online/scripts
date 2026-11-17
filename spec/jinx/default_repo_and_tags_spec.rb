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

          it "matches nothing when neither the name nor a tag matches" do
            Service.run("script search zzzznotatagzzzz")
            expect(game_output).to include("found 0 matches")
          end
        end

        describe "gui" do
          it "explains that the GUI needs a Lich with WebUI when it is missing" do
            expect(defined?(::Lich::API)).to be_nil
            expect { Service.run("gui") }.not_to raise_error
            expect(game_output).to include("The jinx GUI needs a newer Lich")
          end

          it "keeps routing output into the open window after jinx.lic is reloaded" do
            # every ;jinx run reloads the file; output routing must survive that
            load "scripts/jinx.lic"
            GUI.instance_variable_set(:@log, [])
            GUI.instance_variable_set(:@alive, true)
            captured = GUI.capture_output { Log.mono("<b>go2.lic</b> (repo: elanthia-online)") }
            expect(captured).to eq(["go2.lic (repo: elanthia-online)"])
            Log.mono("installed &lt;go2&gt;")
            expect(GUI.instance_variable_get(:@log)).to eq(["installed <go2>"])
            expect(game_output).not_to include("go2")
          ensure
            GUI.instance_variable_set(:@alive, false)
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
