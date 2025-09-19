module SqlLogFilter
  NOISY_SQL_QUERY = 'SELECT "batch_processors".* FROM "batch_processors" WHERE (pending_count > 0)'

  # Redefine the 'sql' method from ActiveRecord's LogSubscriber.
  def sql(event)
    # Check if the SQL query in the log event payload includes our noisy query text.
    # If it does, we simply do nothing (return) and the log is skipped.
    return if event.payload[:sql].include?(NOISY_SQL_QUERY)
    super
  end
end

ActiveRecord::LogSubscriber.prepend(SqlLogFilter)
