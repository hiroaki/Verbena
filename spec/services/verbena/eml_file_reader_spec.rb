require 'rails_helper'

RSpec.describe Verbena::EmlFileReader do
  class DummyReader
    include Verbena::EmlFileReader
  end

  let(:reader) { DummyReader.new }

  describe '#read_eml_from_file!' do
    it 'raises when path is blank' do
      expect { reader.read_eml_from_file!(nil) }.to raise_error(Verbena::EmlFileReader::MissingPathError, /eml file path is required/)
    end

    it 'raises when file not found' do
      expect { reader.read_eml_from_file!('/path/does/not/exist.eml') }.to raise_error(Verbena::EmlFileReader::FileNotFoundError, /File not found/)
    end

    it 'raises when file is not readable' do
      file = Tempfile.new(['unreadable', '.eml'])
      begin
        path = file.path
        allow(File).to receive(:read).with(path).and_raise(Errno::EACCES)

        expect { reader.read_eml_from_file!(path) }.to raise_error(Verbena::EmlFileReader::FileNotReadableError, /File not readable/)
      ensure
        file.unlink
      end
    end

    it 'raises when Mail cannot parse EML' do
      file = Tempfile.new(['bad', '.eml'])
      begin
        file.write("not a valid eml content")
        file.close

        allow(Mail).to receive(:new).and_raise(StandardError.new('parse error'))

        expect { reader.read_eml_from_file!(file.path) }.to raise_error(Verbena::EmlFileReader::InvalidEmlError, /Invalid EML format/)
      ensure
        file.unlink
      end
    end

    # recipient validation is handled by MailQueuesService#create_mail_queues_by_eml!

    it 'returns eml string when valid' do
      file = Tempfile.new(['valid', '.eml'])
      begin
        file.write("From: sender@example.com\r\nTo: recipient@example.com\r\n\r\nHello")
        file.close

        content = reader.read_eml_from_file!(file.path)
        expect(content).to include('To: recipient@example.com')
      ensure
        file.unlink
      end
    end
  end
end
