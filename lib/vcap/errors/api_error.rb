module VCAP
  module Errors
    class ApiError < StandardError
      attr_accessor :args
      attr_accessor :details

      def self.new_from_details(name, *args)
        details = Details.new(name)
        api_error = new
        api_error.details = details
        api_error.args = args
        api_error
      end

      def message
        formatted_args = args.map do |arg|
          (arg.is_a? Array) ? arg.map(&:to_s).join(', ') : arg.to_s
        end

        begin
          sprintf(I18n.translate(details.name, raise: true, :locale => I18n.locale), *formatted_args)
        rescue I18n::MissingTranslationData => e
          sprintf(details.message_format, *formatted_args)
        end
      end

      def code
        details.code
      end

      def name
        details.name
      end

      def response_code
        details.response_code
      end
    end
  end
end


