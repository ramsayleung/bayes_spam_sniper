class TokenizationSamplesController < ApplicationController
  def new
    @trained_messages = TrainedMessage.order("RANDOM()").limit(5)
    if @trained_messages.any?
      service = SpamClassifierService.new(0, "dummy")
      @samples = @trained_messages.map do |msg|
        {
          original: msg.message,
          cleaned: TextCleaner.call(msg.message),
          tokens: service.tokenize(msg.message)
        }
      end
    else
      @samples = []
    end
  end
end
