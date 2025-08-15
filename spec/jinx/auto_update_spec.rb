require 'tmpdir'
require "rack"
require 'webmock'

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

module Jinx
  describe "Auto-Update" do
    unless ENV['ENABLE_EXTERNAL_NETWORKING'] && !%w[false no n 0].include?(ENV['ENABLE_EXTERNAL_NETWORKING'].downcase)
      before(:all) do
        WebMock.enable!
        {
          'core'    => 'repo.elanthia.online',
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
      $data_dir =  Dir.mktmpdir("data")
      $script_dir = Dir.mktmpdir("scripts")
      $lich_dir = Dir.mktmpdir("lich")
      Setup.apply
      game_output
    end
    
    describe "Metadata.all_installed" do
      it "returns empty array when no assets are installed" do
        expect(Metadata.all_installed).to eq([])
      end
      
      it "tracks installed scripts" do
        Service.run("script install go2")
        game_output
        
        installed = Metadata.all_installed
        expect(installed.size).to eq(1)
        expect(installed.first[:name]).to eq("go2.lic")
        expect(installed.first[:type]).to eq("script")
        expect(installed.first[:metadata][:repo]).to eq(:core)
      end
      
      it "tracks installed data files" do
        Service.run("data install spell-list.xml")
        game_output
        
        installed = Metadata.all_installed
        expect(installed.size).to eq(1)
        expect(installed.first[:name]).to eq("spell-list.xml")
        expect(installed.first[:type]).to eq("data")
        expect(installed.first[:metadata][:repo]).to eq(:core)
      end
      
      it "tracks multiple installed assets" do
        Service.run("script install go2")
        Service.run("data install spell-list.xml")
        game_output
        
        installed = Metadata.all_installed
        expect(installed.size).to eq(2)
        
        names = installed.map { |i| i[:name] }
        expect(names).to include("go2.lic")
        expect(names).to include("spell-list.xml")
      end
      
      it "excludes engine assets from all_installed" do
        # Even if we somehow had engine metadata, it should not be included
        # This is important for safety
        Service.run("engine update")
        game_output
        
        # all_installed should not include engines
        installed = Metadata.all_installed
        expect(installed.none? { |i| i[:type] == "engine" }).to be true
      end
    end
    
    describe "AutoUpdater.check_for_updates" do
      it "reports no updates when nothing is installed" do
        updates = AutoUpdater.check_for_updates
        output = game_output
        
        expect(updates).to eq([])
        expect(output).to include("No jinx-installed assets found")
      end
      
      it "reports no updates when all assets are current" do
        Service.run("script install go2")
        game_output
        
        updates = AutoUpdater.check_for_updates
        output = game_output
        
        expect(updates).to eq([])
        expect(output).to include("all up to date!")
      end
      
      it "detects available updates when digest differs" do
        # Install an asset
        Service.run("script install go2")
        game_output
        
        # Simulate the local file being outdated by modifying its content
        local_file = File.join($script_dir, "go2.lic")
        File.write(local_file, "modified content that will have different hash")
        
        updates = AutoUpdater.check_for_updates
        output = game_output
        
        expect(updates.size).to eq(1)
        expect(updates.first[:name]).to eq("go2.lic")
        expect(output).to include("1 updates:")
        expect(output).to include("go2.lic(script)")
      end
      
      it "handles missing assets in repository" do
        # Install an asset
        Service.run("script install go2")
        game_output
        
        # Simulate the asset being from a non-existent repo
        ScriptMetadata.atomic do |entries|
          entries["go2.lic"][:repo] = :nonexistent
          entries
        end
        
        updates = AutoUpdater.check_for_updates
        output = game_output
        
        expect(updates).to eq([])
        expect(output).to include("1 errors:")
      end
      
      it "checks multiple assets efficiently" do
        Service.run("script install go2")
        Service.run("script install infomon")
        Service.run("data install spell-list.xml")
        game_output
        
        # Make one asset outdated by modifying its local file
        local_file = File.join($script_dir, "infomon.lic")
        File.write(local_file, "modified content")
        
        updates = AutoUpdater.check_for_updates
        output = game_output
        
        expect(output).to include("Checked 3 assets")
        expect(updates.size).to eq(1)
        expect(updates.first[:name]).to eq("infomon.lic")
      end
    end
    
    describe "AutoUpdater.update_all" do
      it "does nothing when no updates are available" do
        Service.run("script install go2")
        game_output
        
        AutoUpdater.update_all
        output = game_output
        
        expect(output).to include("all up to date!")
      end
      
      it "updates outdated assets" do
        Service.run("script install go2")
        game_output
        
        # Make it outdated by modifying the local file
        local_file = File.join($script_dir, "go2.lic")
        File.write(local_file, "modified content")
        
        AutoUpdater.update_all(force: true)
        output = game_output
        
        expect(output).to include("1 updates: go2.lic(script)")
        expect(output).to include("✓ Updated all 1 assets: go2.lic")
      end
      
      it "respects dry-run flag" do
        Service.run("script install go2")
        game_output
        
        # Make it outdated by modifying the local file
        local_file = File.join($script_dir, "go2.lic")
        File.write(local_file, "modified content")
        
        AutoUpdater.update_all(dry_run: true)
        output = game_output
        
        expect(output).to include("1 updates:")
        expect(output).to include("Dry run - no changes will be made")
        expect(output).not_to include("Updating")
        
        # Verify the local file is still modified (no actual update)
        local_file = File.join($script_dir, "go2.lic")
        expect(File.read(local_file)).to eq("modified content")
      end
      
      it "handles failed updates gracefully" do
        Service.run("script install go2")
        Service.run("script install infomon")
        game_output
        
        # Make both outdated by modifying local files
        File.write(File.join($script_dir, "go2.lic"), "modified_go2")
        File.write(File.join($script_dir, "infomon.lic"), "modified_infomon")
        
        # Make go2.lic read-only to cause update failure
        go2_path = File.join($script_dir, "go2.lic")
        File.chmod(0444, go2_path) if File.exist?(go2_path)
        
        AutoUpdater.update_all(force: true)
        output = game_output
        
        # At least one should succeed (infomon), and errors should be clean
        expect(output).to match(/✓ Updated.*✗ Failed/)
        # Error messages should be cleaned up (no escaped newlines)
        expect(output).not_to include("\\n")
        # Individual error lines should include specific update command
        expect(output).to include(";jinx update go2.lic --force")
      end
      
      it "reports multiple updates with progress" do
        Service.run("script install go2")
        Service.run("script install infomon")
        Service.run("data install spell-list.xml")
        game_output
        
        # Make all outdated by modifying local files
        File.write(File.join($script_dir, "go2.lic"), "modified1")
        File.write(File.join($script_dir, "infomon.lic"), "modified2")
        File.write(File.join($data_dir, "spell-list.xml"), "modified3")
        
        AutoUpdater.update_all(force: true)
        output = game_output
        
        expect(output).to include("3 updates: go2.lic(script), infomon.lic(script), spell-list.xml(data)")
        expect(output).to include("✓ Updated all 3 assets: go2.lic, infomon.lic, spell-list.xml")
      end
    end
    
    describe "CLI integration" do
      it "handles ;jinx auto-update command" do
        Service.run("script install go2")
        game_output
        
        Service.run("auto-update")
        output = game_output
        
        expect(output).to include("all up to date!")
      end
      
      it "handles ;jinx auto-update --dry-run" do
        Service.run("script install go2")
        game_output
        
        # Make it outdated by modifying the local file
        local_file = File.join($script_dir, "go2.lic")
        File.write(local_file, "modified content")
        
        Service.run("auto-update --dry-run")
        output = game_output
        
        expect(output).to include("Dry run - no changes will be made")
      end
      
      it "handles ;jinx auto-update --force" do
        Service.run("script install go2")
        game_output
        File.write(File.join($script_dir, "go2.lic"), "modified")
        
        # Make it outdated by modifying the local file
        local_file = File.join($script_dir, "go2.lic")
        File.write(local_file, "modified content")
        
        Service.run("auto-update --force")
        output = game_output
        
        expect(output).to include("✓ Updated all 1 assets: go2.lic")
      end
    end
  end
end