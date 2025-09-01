require "jieba_rb"

dictionary_path = Rails.root.join("vendor", "dictionaries", "user.dict.utf8").to_s
if File.exist?(dictionary_path)
  # Create a globally accessible constant that holds the initialized segmenter instance.
  JIEBA = JiebaRb::Segment.new(user_dict: dictionary_path)
  puts "JiebaRb segmenter initialized with custom dictionary."
else
  JIEBA = JiebaRb::Segment.new
  warn "WARNING: JiebaRb custom dictionary not found at #{dictionary_path}. Using default dictionary."
end
