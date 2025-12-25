module Verbena
  module EmlFileReader
    class Error < StandardError; end
    class MissingPathError < Error; end
    class FileNotFoundError < Error; end
    class FileNotReadableError < Error; end
    class InvalidEmlError < Error; end
    class NoRecipientsError < Error; end

    # Read EML content from a file path, raising ArgumentError for common user errors.
    # Returns the file content as a string.
    def read_eml_from_file!(path)
      raise MissingPathError, 'eml file path is required' if path.blank?

      begin
        eml = File.read(path)
      rescue Errno::ENOENT
        raise FileNotFoundError, "File not found: #{path}"
      rescue Errno::EACCES
        raise FileNotReadableError, "File not readable: #{path}"
      end

      # Basic EML validation: can Mail parse it and does it contain recipients?
      begin
        message = Mail.new(eml)
      rescue => e
        raise InvalidEmlError, "Invalid EML format: #{e.class}: #{e.message}"
      end

      destinations = Array(message.destinations).map(&:to_s).reject(&:blank?)
      if destinations.empty?
        raise NoRecipientsError, 'No recipients (To/Cc/Bcc) found in EML'
      end

      eml
    end
  end
end
