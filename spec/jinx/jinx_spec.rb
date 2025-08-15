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

module Jinx
  describe Setup do
    it "bails when $data_dir doesn't exist" do
      $data_dir = nil
      expect { Setup.apply }.to raise_error(Jinx::Error, "$data_dir is not String")
    end

    it "creates the $data_dir/_jinx folder" do
      $data_dir = Dir.mktmpdir()
      Setup.apply
      Repo.lookup("core")
      Repo.lookup("elanthia-online")
    end
  end

  describe Service do
    unless ENV['ENABLE_EXTERNAL_NETWORKING'] && !%w[false no n 0].include?(ENV['ENABLE_EXTERNAL_NETWORKING'].downcase)
      before(:all) do
        WebMock.enable!
        {
          'core'    => 'repo.elanthia.online',
          'extras'  => 'extras.repo.elanthia.online',
          'archive' => 'archive.lich.elanthia.online',
          'gtk3'    => 'gtk3.elanthia.online',
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

    describe "repo" do
      it "repo list" do
        Service.run("repo list")
        output = game_output
        expect(output).to include("core:")
        expect(output).to include("elanthia-online:")
      end

      it "(core) repo info" do
        Service.run("repo info core")
        output = game_output
        expect(output).to include("scripts:")
        expect(output).to include("go2.lic")
        expect(output).to include("infomon.lic")
        # TODO: expect data info in repo info response too
      end

      it "repo add" do
        Service.run("repo add archive https://archive.lich.elanthia.online")
        Repo.lookup("archive")
        # specificity is required
        expect { Service.run("script install noop") }
          .to raise_error(Jinx::Error, /more than one repo has/)

        # make a clean script dir
        $script_dir = Dir.mktmpdir("scripts")
        # ensure installing go2 from this archive works
        game_output # clear
        Service.run("script install go2 --repo=core")
        installed_file = File.join($script_dir, "go2.lic")
        expect(File.exist?(installed_file)).to be true
        install_output = game_output
        expect(install_output).to include("installing go2.lic from repo:core")
        Service.run("script install go2 --repo=core")
        install_output = game_output
        expect(install_output).to include("go2.lic from repo:core already installed")
        Service.run("script update go2 --repo=core")
        update_output = game_output
        expect(update_output).to include("go2.lic from repo:core already installed")

        expect(File.exist?(File.join($data_dir, '_jinx', 'repos.yaml'))).to be true
        expect(File.exist?(File.join($data_dir, '_jinx', 'scripts.yaml'))).to be true
      end

      it "repo rm" do
        Service.run("repo add archive https://archive.lich.elanthia.online")
        game_output
        Service.run("repo rm archive")
        expect(Repo.find { |repo| repo[:name].eql?(:archive) })
          .to be_nil

        rm_output = game_output
        expect(rm_output).to include("repo(archive) has been removed")

        expect { Service.run("repo rm archive") }
          .to raise_error(Jinx::Error,
                          %r[repo\(archive\) is not known])
      end

      it "repo can readd a previously removed repo" do
        Service.run("repo add archive https://archive.lich.elanthia.online")
        game_output
        Service.run("repo rm archive")
        expect(Repo.find { |repo| repo[:name].eql?(:archive) })
          .to be_nil

        Service.run("repo add archive https://archive.lich.elanthia.online")
        Repo.lookup("archive")
      end

      it "repo change {repo:name} {repo:url}" do
        Service.run("repo change core https://example.com")
        change_output = game_output
        expect(change_output).to include("repo(core) has been changed")
        core = Repo.lookup("core")
        expect(core[:url]).to eq(%[https://example.com])

        expect { Service.run("repo change _fake_ https://example.com") }
          .to raise_error(Jinx::Error,
                          %r[repo\(_fake_\) is not known])
      end
    end

    describe "script" do
      describe "(core) script install" do
        let(:local_asset_path) { File.join($script_dir, "go2.lic") }

        it "will install the first time cleanly on 1-to-1" do
          Service.run("script install go2")

          _first_attempt = game_output
          expect(File.exist?(local_asset_path)).to be true
        end

        it "is a noop is the local file matches the expected digest" do
          Service.run("script install go2")
          game_output # clear
          Service.run("script install go2")
          output = game_output

          expect(output).to include("go2.lic from repo:core already installed")
          expect(File.exist?(local_asset_path)).to be true
        end

        it "will not accidentally overwrite already existing script if the digests don't match" do
          Service.run("script install go2")
          game_output # clear
          File.write(local_asset_path, "modified")

          expect { Service.run("script install go2") }
            .to raise_error(Jinx::Error, /go2.lic already exists/)
          _second_attempt = game_output # clear
        end

        it "will not install/update script when using data option" do
          expect { Service.run("data install go2") }
            .to raise_error(Jinx::Error, /Attempted to download/)

          expect { Service.run("data update go2") }
            .to raise_error(Jinx::Error, /Attempted to download/)
        end

        it "will install over existing script if given --force" do
          Service.run("script install go2")
          game_output # clear
          clean_digest = Digest::SHA1.new
          clean_digest.update(File.read(local_asset_path))
          File.write(local_asset_path, "modified")
          modified_digest = Digest::SHA1.new
          modified_digest.update(File.read(local_asset_path))
          expect(modified_digest.base64digest).to_not eq clean_digest.base64digest

          Service.run("script install --force go2")

          updated_digest = Digest::SHA1.new
          updated_digest.update(File.read(local_asset_path))
          expect(updated_digest.base64digest).to eq clean_digest.base64digest
        end
      end

      describe "(core) script update" do
        let(:local_asset_path) { File.join($script_dir, "go2.lic") }

        it "will install the first time cleanly on 1-to-1" do
          Service.run("script update go2")

          _first_attempt = game_output
          expect(File.exist?(local_asset_path)).to be true
        end

        it "is a noop is the local file matches the expected digest" do
          Service.run("script install go2")
          game_output # clear
          Service.run("script update go2")
          output = game_output

          expect(output).to include("go2.lic from repo:core already installed")
          expect(File.exist?(local_asset_path)).to be true
        end

        it "will not accidentally overwrite already existing script if the digests don't match" do
          Service.run("script install go2")
          game_output # clear
          File.write(local_asset_path, "modified")

          expect { Service.run("script update go2") }
            .to raise_error(Jinx::Error, /go2.lic has been modified/)
        end

        it "will overwrite a modified script if given --force" do
          Service.run("script install go2")
          game_output # clear
          clean_digest = Digest::SHA1.new
          clean_digest.update(File.read(local_asset_path))
          File.write(local_asset_path, "modified")
          modified_digest = Digest::SHA1.new
          modified_digest.update(File.read(local_asset_path))
          expect(modified_digest.base64digest).to_not eq clean_digest.base64digest

          Service.run("script update go2 --force")

          updated_digest = Digest::SHA1.new
          updated_digest.update(File.read(local_asset_path))
          expect(updated_digest.base64digest).to eq clean_digest.base64digest
        end
      end

      it "script info" do
        Service.run("script info noop")
        info_output = game_output
        expect(info_output).to include("noop (repo: elanthia-online, modified:")
        Service.run("repo add archive https://archive.lich.elanthia.online")
        # now two repos advertise noop, so it should error
        expect { Service.run("script info noop") }
          .to raise_error(Jinx::Error,
                          %r[more than one repo has asset\(noop.lic\)])

        expect { Service.run("script info noop --repo=core") }
          .to raise_error(Jinx::Error,
                          %r[repo\(core\) does not advertise asset\(noop.lic\)])
        game_output # clear
        # make sure it checks the elanthia-online repo
        Service.run("script info noop --repo=elanthia-online")
        info_output = game_output
        expect(info_output).to include("noop (repo: elanthia-online, modified:")
        # make sure it checks the archive repo
        Service.run("script info noop --repo=archive")
        info_output = game_output
        expect(info_output).to include("noop (repo: archive, modified:")
      end

      it "script search" do
        Service.run("script search noop")
        search_output = game_output
        expect(search_output).to include("found 1 match")
        Service.run("script search asdfasdfjahksdkfajsdhfka")
        search_output = game_output
        expect(search_output).to include("found 0 matches")
        Service.run("script search noop")
        search_output = game_output
        expect(search_output).to include("found 1 match")
        Service.run("repo add archive https://archive.lich.elanthia.online")
        # regex search
        Service.run("script search ^noop.lic")
        search_output = game_output
        expect(search_output).to include("found 2 matches")
        # repo specific search
        Service.run("script search ^noop.lic --repo=archive")
        search_output = game_output
        expect(search_output).to include("found 1 match")
        expect(search_output).to include("archive>")
      end
    end

    describe "data" do
      let(:local_asset_path) { File.join($data_dir, "spell-list.xml") }

      describe "install" do
        class Spell
          def self.load
          end
        end

        it "will install the first time cleanly on 1-to-1" do
          allow(Spell).to receive(:load)
          Service.run("data install spell-list.xml")

          _first_attempt = game_output
          expect(File.exist?(local_asset_path)).to be true
        end

        it "runs the post-install hook after installing" do
          allow(Spell).to receive(:load)
          Service.run("data install spell-list.xml")

          _first_attempt = game_output
          expect(Spell).to have_received(:load)
        end

        it "is a noop is the local file matches the expected digest" do
          Service.run("data install spell-list.xml")
          game_output # clear
          Service.run("data install spell-list.xml")
          output = game_output

          expect(output).to include("spell-list.xml from repo:core already installed")
          expect(File.exist?(local_asset_path)).to be true
        end

        it "will not accidentally overwrite already existing file if the digests don't match" do
          Service.run("data install spell-list.xml")
          game_output # clear
          File.write(local_asset_path, "modified")

          expect { Service.run("data install spell-list.xml") }
            .to raise_error(Jinx::Error, /spell-list.xml already exists/)
        end

        it "will install over existing file if given --force" do
          Service.run("data install spell-list.xml")
          game_output # clear
          clean_digest = Digest::SHA1.new
          clean_digest.update(File.read(local_asset_path))
          File.write(local_asset_path, "modified")
          modified_digest = Digest::SHA1.new
          modified_digest.update(File.read(local_asset_path))
          expect(modified_digest.base64digest).to_not eq clean_digest.base64digest

          Service.run("data install spell-list.xml --force")

          updated_digest = Digest::SHA1.new
          updated_digest.update(File.read(local_asset_path))
          expect(updated_digest.base64digest).to eq clean_digest.base64digest
        end
      end

      describe "update" do
        it "will install the first time cleanly on 1-to-1" do
          Service.run("data update spell-list.xml")

          _first_attempt = game_output
          expect(File.exist?(local_asset_path)).to be true
        end

        it "is a noop is the local file matches the expected digest" do
          Service.run("data install spell-list.xml")
          game_output # clear
          Service.run("data update spell-list.xml")
          output = game_output

          expect(output).to include("spell-list.xml from repo:core already installed")
          expect(File.exist?(local_asset_path)).to be true
        end

        it "will not accidentally overwrite already existing script if the digests don't match" do
          Service.run("data install spell-list.xml")
          game_output # clear
          File.write(local_asset_path, "modified")

          expect { Service.run("data update spell-list.xml") }
            .to raise_error(Jinx::Error, /spell-list.xml has been modified/)
        end

        it "will overwrite a modified script if given --force" do
          Service.run("data install spell-list.xml")
          game_output # clear
          clean_digest = Digest::SHA1.new
          clean_digest.update(File.read(local_asset_path))
          File.write(local_asset_path, "modified")
          modified_digest = Digest::SHA1.new
          modified_digest.update(File.read(local_asset_path))
          expect(modified_digest.base64digest).to_not eq clean_digest.base64digest

          Service.run("data update spell-list.xml --force")

          updated_digest = Digest::SHA1.new
          updated_digest.update(File.read(local_asset_path))
          expect(updated_digest.base64digest).to eq clean_digest.base64digest
        end
      end

      it "list" do
        Service.run("data list")
        output = game_output
        expect(output).to include("data:")
        expect(output).to include("spell-list.xml")
      end

      it "will not install/update data when using script option" do
        expect { Service.run("script install spell-list.xml") }
          .to raise_error(Jinx::Error, /Attempted to download/)

        expect { Service.run("script update spell-list.xml") }
          .to raise_error(Jinx::Error, /Attempted to download/)
      end
    end

    describe "engine" do
      it "list" do
        Service.run("engine list")
        output = game_output
        expect(output).to include("engines:")
        expect(output).to include("lich.rb")
      end

      describe "update" do
        let(:local_asset_path) { File.join($lich_dir, File.basename($PROGRAM_NAME)) }

        it "will install the first time cleanly on 1-to-1" do
          Service.run("engine update")

          _first_attempt = game_output
          expect(File.exist?(local_asset_path)).to be true
        end

        it "is a noop is the local file matches the expected digest" do
          Service.run("engine update")
          game_output # clear
          Service.run("engine update")
          output = game_output

          expect(output).to include("lich.rb from repo:core already installed")
          expect(File.exist?(local_asset_path)).to be true
        end

        it "will not accidentally overwrite already existing script if the digests don't match" do
          Service.run("engine update")
          game_output # clear
          File.write(local_asset_path, "modified")

          expect { Service.run("engine update") }
            .to raise_error(Jinx::Error, /has been modified/)
        end

        it "will overwrite a modified script if given --force" do
          Service.run("engine update")
          game_output # clear
          clean_digest = Digest::SHA1.new
          clean_digest.update(File.read(local_asset_path))
          File.write(local_asset_path, "modified")
          modified_digest = Digest::SHA1.new
          modified_digest.update(File.read(local_asset_path))
          expect(modified_digest.base64digest).to_not eq clean_digest.base64digest

          Service.run("engine update --force")

          updated_digest = Digest::SHA1.new
          updated_digest.update(File.read(local_asset_path))
          expect(updated_digest.base64digest).to eq clean_digest.base64digest
        end
      end
    end

    describe LichEngine do
      describe "normalize_name" do
        it "given a fully specified name" do
          expect(LichEngine.normalize_name("forked-engine.rb")).to eq "forked-engine.rb"
        end

        it "given nil (e.g. no CLI argument)" do
          expect(LichEngine.normalize_name(nil)).to eq "lich.rb"
        end

        it "given an empty string" do
          expect(LichEngine.normalize_name("")).to eq "lich.rb"
        end

        it "given something probably intended to be lich.rb" do
          expect(LichEngine.normalize_name("lich.rbw")).to eq "lich.rb"
          expect(LichEngine.normalize_name("lich.rb")).to eq "lich.rb"
          expect(LichEngine.normalize_name("lich")).to eq "lich.rb"
        end
      end
    end
  end
end
