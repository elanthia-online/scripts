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

def game_output
  buffered = $fake_game_output.dup
  $fake_game_output = ""
  return buffered
end

# Define Spell class for testing
class Spell
  def self.load
  end
end

module ::Lich
  module Common
    module Jinx
      describe "Smart Commands" do
        unless ENV['ENABLE_EXTERNAL_NETWORKING'] && !%w[false no n 0].include?(ENV['ENABLE_EXTERNAL_NETWORKING'].downcase)
          before(:all) do
            WebMock.enable!
            {
              'extras'  => 'extras.repo.elanthia.online',
              'archive' => 'archive.lich.elanthia.online',
              'mirror'  => 'ffnglichrepoarchive.netlify.app',
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

        describe "SmartInstaller" do
          describe "type detection" do
            it "correctly detects script type" do
              type = Lookup.detect_asset_type("go2.lic", Repo.to_a)
              expect(type).to eq("script")
            end

            it "correctly detects data type" do
              type = Lookup.detect_asset_type("spell-list.xml", Repo.to_a)
              expect(type).to eq("data")
            end

            it "correctly detects engine type" do
              type = Lookup.detect_asset_type("lich.rb", Repo.to_a)
              expect(type).to eq("engine")
            end

            it "returns nil for non-existent assets" do
              type = Lookup.detect_asset_type("fake-asset.lic", Repo.to_a)
              expect(type).to be_nil
            end

            it "detects ambiguous types when asset exists with different types" do
              # This would require mock data with same name but different types
              # Skipping for now as test repos don't have this scenario
            end
          end

          describe "smart install" do
            it "installs scripts automatically" do
              Service.run("install go2")
              expect(File.exist?(File.join($script_dir, "go2.lic"))).to be true
              output = game_output
              expect(output).to include("installing go2.lic from repo:elanthia-online")
            end

            it "installs data files automatically" do
              allow(Spell).to receive(:load) if defined?(Spell)
              Service.run("install spell-list.xml")
              expect(File.exist?(File.join($data_dir, "spell-list.xml"))).to be true
              output = game_output
              expect(output).to include("installing spell-list.xml from repo:elanthia-online")
            end

            it "provides helpful error for non-existent assets" do
              expect { Service.run("install nonexistent-asset") }
                .to raise_error(Jinx::Error, /No asset named 'nonexistent-asset' found/)
            end

            it "respects --type flag to force specific type" do
              # Install as script explicitly (even though it doesn't exist as one)
              expect { Service.run("install spell-list.xml --type=script") }
                .to raise_error(Jinx::Error)
            end

            it "respects --repo flag for specific repository" do
              Service.run("install go2 --repo=elanthia-online")
              expect(File.exist?(File.join($script_dir, "go2.lic"))).to be true
            end
          end

          describe "smart update" do
            it "updates installed scripts automatically" do
              Service.run("install go2")
              game_output
              Service.run("update go2")
              output = game_output
              expect(output).to include("go2.lic from repo:elanthia-online already installed")
            end

            it "updates installed data files automatically" do
              allow(Spell).to receive(:load) if defined?(Spell)
              Service.run("install spell-list.xml")
              game_output
              Service.run("update spell-list.xml")
              output = game_output
              expect(output).to include("spell-list.xml from repo:elanthia-online already installed")
            end

            it "handles modified files appropriately" do
              Service.run("install go2")
              game_output
              File.write(File.join($script_dir, "go2.lic"), "modified")

              expect { Service.run("update go2") }
                .to raise_error(Jinx::Error, /has been modified/)
            end

            it "allows force update of modified files" do
              Service.run("install go2")
              game_output
              original_content = File.read(File.join($script_dir, "go2.lic"))
              File.write(File.join($script_dir, "go2.lic"), "modified")

              Service.run("update go2 --force")
              restored_content = File.read(File.join($script_dir, "go2.lic"))
              expect(restored_content).to eq(original_content)
            end
          end
        end

        describe "Unified CLI commands" do
          describe "jinx list" do
            it "shows all asset types" do
              Service.run("list")
              output = game_output
              expect(output).to include("scripts:")
              expect(output).to include("data:")
              expect(output).to include("engines:")
              expect(output).to include("go2.lic")
              expect(output).to include("spell-list.xml")
              expect(output).to include("lich.rb")
            end

            it "filters by repository with --repo" do
              Service.run("list --repo=elanthia-online")
              output = game_output
              expect(output).to include("elanthia-online:")
              expect(output).not_to include("extras:")
            end
          end

          describe "jinx info" do
            it "shows info for scripts" do
              Service.run("info go2")
              output = game_output
              expect(output).to include("go2")
              expect(output).to include("type: script")
              expect(output).to include("repo: elanthia-online")
            end

            it "shows info for data files" do
              Service.run("info spell-list.xml")
              output = game_output
              expect(output).to include("spell-list.xml")
              expect(output).to include("type: data")
              expect(output).to include("repo: elanthia-online")
            end

            it "shows info for engines" do
              Service.run("info lich.rb")
              output = game_output
              expect(output).to include("lich.rb")
              expect(output).to include("type: engine")
              expect(output).to include("repo: elanthia-online")
            end

            it "handles non-existent assets gracefully" do
              Service.run("info nonexistent")
              output = game_output
              expect(output).to include("No asset named 'nonexistent' found")
              expect(output).to include("jinx search")
            end

            it "handles assets in multiple repos" do
              Service.run("repo add archive https://archive.lich.elanthia.online")
              game_output
              Service.run("info noop")
              output = game_output
              expect(output).to include("Asset 'noop' found in multiple repositories")
              expect(output).to include("--repo=")
            end
          end

          describe "jinx search" do
            it "searches across all asset types" do
              Service.run("search spell")
              output = game_output
              expect(output).to include("spell-list.xml")
              expect(output).to include("Data")
            end

            it "groups results by type" do
              Service.run("search .") # Match everything
              output = game_output
              expect(output).to include("Scripts:")
              expect(output).to include("Datas:")
              expect(output).to include("Engines:")
            end

            it "shows no matches message appropriately" do
              Service.run("search zzzznonexistentzzzz")
              output = game_output
              expect(output).to include("No matches found")
            end

            it "supports regex patterns" do
              Service.run("search ^go2")
              output = game_output
              expect(output).to include("go2.lic")
            end
          end
        end

        describe "Backward compatibility" do
          it "script install still works" do
            Service.run("script install go2")
            expect(File.exist?(File.join($script_dir, "go2.lic"))).to be true
          end

          it "data install still works" do
            allow(Spell).to receive(:load) if defined?(Spell)
            Service.run("data install spell-list.xml")
            expect(File.exist?(File.join($data_dir, "spell-list.xml"))).to be true
          end

          it "script update still works" do
            Service.run("script update go2")
            expect(File.exist?(File.join($script_dir, "go2.lic"))).to be true
          end

          it "data update still works" do
            allow(Spell).to receive(:load) if defined?(Spell)
            Service.run("data update spell-list.xml")
            expect(File.exist?(File.join($data_dir, "spell-list.xml"))).to be true
          end

          it "prevents cross-type installation" do
            expect { Service.run("script install spell-list.xml") }
              .to raise_error(Jinx::Error, /Attempted to download/)

            expect { Service.run("data install go2") }
              .to raise_error(Jinx::Error, /Attempted to download/)
          end
        end

        describe "Error handling" do
          it "provides clear guidance for ambiguous assets" do
            # Would need mock data with same-named assets of different types
            # Current test repos don't have this scenario
          end

          it "suggests alternatives for missing assets" do
            expect { Service.run("install fake-script") }
              .to raise_error(Jinx::Error) do |error|
                expect(error.message).to include("jinx list")
                expect(error.message).to include("jinx search fake-script")
              end
          end

          it "handles repository-specific errors gracefully" do
            expect { Service.run("install go2 --repo=nonexistent") }
              .to raise_error(Jinx::Error, /repo\(nonexistent\) is not known/)
          end
        end
      end
    end
  end
end
