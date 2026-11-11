# frozen_string_literal: true

require 'tmpdir'
require 'zlib'
require 'stringio'

# log_search.lic runs as it loads (gem installs, arguments, the scan), so
# only its LogSearchFiles module, which has no side effects, is loaded here,
# from the script's own source.
module LogSearchSpec
  SOURCE = File.read(File.expand_path('../../scripts/log_search.lic', __dir__), mode: 'rb').gsub("\r\n", "\n")
  START = SOURCE.index("module LogSearchFiles\n")
  STOP = SOURCE.index("\nmodule LogSearch\n")
  module_eval(SOURCE[START...STOP])
end

RSpec.describe 'log_search.lic LogSearchFiles' do
  let(:files) { LogSearchSpec::LogSearchFiles }
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  def write(name, text) = File.join(dir, name).tap { |path| File.binwrite(path, text) }

  def gzip(text, level = Zlib::DEFAULT_COMPRESSION)
    io = StringIO.new(+'')
    gz = Zlib::GzipWriter.new(io, level)
    gz.write(text)
    gz.finish
    io.string
  end

  describe '.paths' do
    it 'lists plain and gzipped logs in name order, one path per log, the plain one when both exist' do
      gz_only = write('2024-08-01_10-00-00.log.gz', gzip("a\n"))
      plain = write('2024-08-02_10-00-00.log', "b\n")
      write('2024-08-02_10-00-00.log.gz', gzip("b\n"))
      later = write('2024-08-03_10-00-00.log', "c\n")
      write('notes.txt', "x\n")
      write('2024-08-04_10-00-00.xml.gz', gzip("<x/>\n"))

      expect(files.paths(dir)).to eq([gz_only, plain, later])
    end

    it 'lists only .txt files with txt' do
      write('2024-08-01_10-00-00.log', "a\n")
      txt = write('wrayth.txt', "x\n")

      expect(files.paths(dir, txt: true)).to eq([txt])
    end

    # A log.lic sweep can delete x.log right after the listing found both.
    it 'keeps only the plain file when a sweep deletes it right after the listing' do
      plain = write('2024-08-02_10-00-00.log', "b\n")
      write('2024-08-02_10-00-00.log.gz', gzip("b\n"))
      allow(Dir).to receive(:glob).and_wrap_original do |original, *args|
        original.call(*args).tap { File.delete(plain) if File.exist?(plain) }
      end

      expect(files.paths(dir)).to eq([plain])
    end
  end

  describe '.file_date' do
    it 'takes the date from a plain or a gzipped log name' do
      expect(files.file_date('/logs/2024-08-01_12-00-00.log')).to eq('2024-08-01')
      expect(files.file_date('/logs/2024-08-01_12-00-00.log.gz')).to eq('2024-08-01')
      expect(files.file_date('/logs/2024-08-01_12-00-00_01.log.gz')).to eq('2024-08-01')
    end
  end

  describe '.lines' do
    let(:found) { '12:00:01: You notice a scintillating mote of gemstone dust on the ground and gather it quickly.' }

    it 'reads a gzipped log like a plain one, chomped, invalid bytes replaced' do
      text = "#{found}\r\n#{[0xFF].pack('C')}bad\n"
      plain = write('2024-08-01_10-00-00.log', text)
      gz = write('2024-08-02_10-00-00.log.gz', gzip(text))

      expect(files.lines(gz)).to eq(files.lines(plain))
      expect(files.lines(gz)).to eq([found, "#{[0xFFFD].pack('U')}bad"])
    end

    it 'reads every member, also one that starts on a 2048-byte boundary' do
      first = gzip("#{'A' * 2024}\n", Zlib::NO_COMPRESSION)
      expect(first.bytesize).to eq(2048)
      gz = write('2024-08-01_10-00-00.log.gz', first + gzip("#{found}\n"))

      expect(files.lines(gz).last).to eq(found)
    end

    # mrhoribu: one unreadable file must not end the run before the
    # results are saved.
    {
      'truncated'                => ->(gz) { gz[0, gz.bytesize / 2] },
      'followed by zero padding' => ->(gz) { gz + ("\0" * 64) },
      'followed by other bytes'  => ->(gz) { gz + 'junk' },
      'empty'                    => ->(_gz) { '' }
    }.each do |label, damage|
      it "gives nil and the error for a damaged .gz (#{label}) instead of raising" do
        gz = write('2024-08-01_10-00-00.log.gz', damage.call(gzip("#{found}\n" * 50)))
        errors = []

        expect(files.lines(gz) { |error| errors << error }).to be_nil
        expect(errors.size).to eq(1)
        expect(errors.first).to be_a(Zlib::Error)
      end
    end

    it 'gives nil and the error for a log that is not there' do
      errors = []

      expect(files.lines(File.join(dir, '2024-08-01_10-00-00.log')) { |error| errors << error }).to be_nil
      expect(errors.map(&:class)).to eq([Errno::ENOENT])
    end

    # A sweep can delete x.log between any existence check and the read:
    # deleted right after File.exist? says it is there, or right before the
    # read, whichever the code does.
    it 'reads the .gz when a sweep deletes the plain file between the check and the read' do
      plain = write('2024-08-01_10-00-00.log', "#{found}\n")
      write('2024-08-01_10-00-00.log.gz', gzip("#{found}\n"))
      swept = false
      sweep = -> { FileUtils.rm_f(plain) unless swept; swept = true }
      allow(File).to(receive(:exist?).and_wrap_original { |original, path| original.call(path).tap { sweep.call if path == plain } })
      allow(File).to receive(:binread).and_wrap_original do |original, path, *args|
        sweep.call if path == plain
        original.call(path, *args)
      end

      expect(files.lines(plain)).to eq([found])
    end

    it 'reads the .gz of a listed .log that was compressed before it was read' do
      plain = File.join(dir, '2024-08-01_10-00-00.log')
      write('2024-08-01_10-00-00.log.gz', gzip("#{found}\n"))

      expect(files.lines(plain)).to eq([found])
    end
  end
end
