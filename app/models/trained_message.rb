class TrainedMessage < ApplicationRecord
  enum :message_type, { spam: 0, ham: 1 }
end
