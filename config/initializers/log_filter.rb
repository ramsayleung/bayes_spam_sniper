module SqlLogFilter
  NOISY_SQL_QUERIES = [
    'SELECT "batch_processors".* FROM "batch_processors" WHERE (pending_count > 0)',
    'UPDATE "solid_queue_processes" SET "last_heartbeat_at"',
    'SELECT "solid_queue_processes".* FROM "solid_queue_processes"',
    'UPDATE "group_classifier_states" SET "spam_counts"',
    'UPDATE "group_classifier_states" SET "ham_counts"'
  ].freeze

  # Redefine the 'sql' method from ActiveRecord's LogSubscriber.
  def sql(event)
    sql_query = event.payload[:sql]

    # Check if the SQL query includes any of our noisy query substrings.
    return if NOISY_SQL_QUERIES.any? { |noisy_query| sql_query.include?(noisy_query) }

    super
  end
end

ActiveRecord::LogSubscriber.prepend(SqlLogFilter)
