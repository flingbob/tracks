class Stats
  SECONDS_PER_DAY = 86400

  attr_reader :current_user

  def initialize(current_user)
    @current_user = user
  end

  def difference_in_days(date1, date2)
    return ((date1.utc.at_midnight-date2.utc.at_midnight)/SECONDS_PER_DAY).to_i
  end

  def compute
    @me = self # for meta programming

    # default chart dimensions
    @chart_width=460
    @chart_height=250
    @pie_width=@chart_width
    @pie_height=325

    # get the current date wih time set to 0:0
    @today = Time.zone.now.utc.beginning_of_day

    # define cut_off date and discard the time for a month, 3 months and a year
    @cut_off_year = 12.months.ago.beginning_of_day
    @cut_off_year_plus3 = 15.months.ago.beginning_of_day
    @cut_off_month = 1.month.ago.beginning_of_day
    @cut_off_3months = 3.months.ago.beginning_of_day

    @page_title = t('stats.index_title')

    @first_action = current_user.todos.reorder("created_at ASC").first
    @tags_count = current_user.todos.find_by_sql([
                                                   "SELECT tags.id as id "+
                                                     "FROM tags, taggings, todos "+
                                                     "WHERE tags.id = taggings.tag_id " +
                                                     "AND taggings.taggable_id = todos.id " +
                                                     "AND todos.user_id = #{current_user.id}"]).size
    tag_ids = current_user.todos.find_by_sql([
                                               "SELECT DISTINCT tags.id as id "+
                                                 "FROM tags, taggings, todos "+
                                                 "WHERE tags.id = taggings.tag_id " +
                                                 "AND taggings.taggable_id = todos.id "+
                                                 "AND todos.user_id = #{current_user.id}"])
    tags_ids_s = tag_ids.map(&:id).sort.join(",")
    if tags_ids_s.blank?
      rv = {}   # return empty hash for .size to work
    else
      rv =  Tag.where("id in (#{tags_ids_s})")
    end
    @unique_tags_count = rv.size

    @hidden_contexts = current_user.contexts.hidden

    #get_stats_actions
                                                     # time to complete
    @completed_actions = current_user.todos.completed.select("completed_at, created_at")

    actions_sum, actions_max = 0,0
    actions_min = @completed_actions.first ? @completed_actions.first.completed_at - @completed_actions.first.created_at : 0

    @completed_actions.each do |r|
      actions_sum += (r.completed_at - r.created_at)
      actions_max = [(r.completed_at - r.created_at), actions_max].max
      actions_min = [(r.completed_at - r.created_at), actions_min].min
    end

    sum_actions = @completed_actions.size
    sum_actions = 1 if sum_actions==0 # to prevent dividing by zero

    @actions_avg_ttc = (actions_sum/sum_actions)/SECONDS_PER_DAY
    @actions_max_ttc = actions_max/SECONDS_PER_DAY
    @actions_min_ttc = actions_min/SECONDS_PER_DAY

    min_ttc_sec = Time.utc(2000,1,1,0,0)+actions_min # convert to a datetime
    @actions_min_ttc_sec = (min_ttc_sec).strftime("%H:%M:%S")
    @actions_min_ttc_sec = (actions_min / SECONDS_PER_DAY).round.to_s + " days " + @actions_min_ttc_sec if actions_min > SECONDS_PER_DAY

    # get count of actions created and actions done in the past 30 days.
    @sum_actions_done_last30days = current_user.todos.completed.completed_after(@cut_off_month).count
    @sum_actions_created_last30days = current_user.todos.created_after(@cut_off_month).count

    # get count of actions done in the past 12 months.
    @sum_actions_done_last12months = current_user.todos.completed.completed_after(@cut_off_year).count
    @sum_actions_created_last12months = current_user.todos.created_after(@cut_off_year).count

    ####get_stats_contexts

    # get action count per context for TOP 5
    #
    # Went from GROUP BY c.id to c.id, c.name for compatibility with postgresql.
    # Since the name is forced to be unique, this should work.
    @actions_per_context = current_user.contexts.find_by_sql(
      "SELECT c.id AS id, c.name AS name, count(*) AS total "+
        "FROM contexts c, todos t "+
        "WHERE t.context_id=c.id "+
        "AND t.user_id=#{current_user.id} " +
        "GROUP BY c.id, c.name ORDER BY total DESC " +
        "LIMIT 5"
    )

    # get incomplete action count per visible context for TOP 5
    #
    # Went from GROUP BY c.id to c.id, c.name for compatibility with postgresql.
    # Since the name is forced to be unique, this should work.
    @running_actions_per_context = current_user.contexts.find_by_sql(
      "SELECT c.id AS id, c.name AS name, count(*) AS total "+
        "FROM contexts c, todos t "+
        "WHERE t.context_id=c.id AND t.completed_at IS NULL AND NOT c.hide "+
        "AND t.user_id=#{current_user.id} " +
        "GROUP BY c.id, c.name ORDER BY total DESC " +
        "LIMIT 5"
    )

    #### get_stats_projects
    # get the first 10 projects and their action count (all actions)
    #
    # Went from GROUP BY p.id to p.name for compatibility with postgresql. Since
    # the name is forced to be unique, this should work.
    @projects_and_actions = current_user.projects.find_by_sql(
      "SELECT p.id, p.name, count(*) AS count "+
        "FROM projects p, todos t "+
        "WHERE p.id = t.project_id "+
        "AND t.user_id=#{current_user.id} " +
        "GROUP BY p.id, p.name "+
        "ORDER BY count DESC " +
        "LIMIT 10"
    )

    # get the first 10 projects with their actions count of actions that have
    # been created or completed the past 30 days

    # using GROUP BY p.name (was: p.id) for compatibility with Postgresql. Since
    # you cannot create two contexts with the same name, this will work.
    @projects_and_actions_last30days = current_user.projects.find_by_sql([
                                                                           "SELECT p.id, p.name, count(*) AS count "+
                                                                             "FROM todos t, projects p "+
                                                                             "WHERE t.project_id = p.id AND "+
                                                                             "      (t.created_at > ? OR t.completed_at > ?) "+
                                                                             "AND t.user_id=#{current_user.id} " +
                                                                             "GROUP BY p.id, p.name "+
                                                                             "ORDER BY count DESC " +
                                                                             "LIMIT 10", @cut_off_month, @cut_off_month]
    )

    # get the first 10 projects and their running time (creation date versus
    # now())
    @projects_and_runtime_sql = current_user.projects.find_by_sql(
      "SELECT id, name, created_at "+
        "FROM projects "+
        "WHERE state='active' "+
        "AND user_id=#{current_user.id} "+
        "ORDER BY created_at ASC "+
        "LIMIT 10"
    )

    i=0
    @projects_and_runtime = Array.new(10, [-1, t('common.not_available_abbr'), t('common.not_available_abbr')])
    @projects_and_runtime_sql.each do |r|
      days = difference_in_days(@today, r.created_at)
      # add one so that a project that you just created returns 1 day
      @projects_and_runtime[i]=[r.id, r.name, days.to_i+1]
      i += 1
    end



    #get_stats_tags
    # tag cloud code inspired by this article
    #  http://www.juixe.com/techknow/index.php/2006/07/15/acts-as-taggable-tag-cloud/

    levels=10
    # TODO: parameterize limit

    # Get the tag cloud for all tags for actions
    query = "SELECT tags.id, name, count(*) AS count"
    query << " FROM taggings, tags, todos"
    query << " WHERE tags.id = tag_id"
    query << " AND taggings.taggable_id = todos.id"
    query << " AND todos.user_id="+current_user.id.to_s+" "
    query << " AND taggings.taggable_type='Todo' "
    query << " GROUP BY tags.id, tags.name"
    query << " ORDER BY count DESC, name"
    query << " LIMIT 100"
    @tags_for_cloud = Tag.find_by_sql(query).sort_by { |tag| tag.name.downcase }

    max, @tags_min = 0, 0
    @tags_for_cloud.each { |t|
      max = [t.count.to_i, max].max
      @tags_min = [t.count.to_i, @tags_min].min
    }

    @tags_divisor = ((max - @tags_min) / levels) + 1

    # Get the tag cloud for all tags for actions
    query = "SELECT tags.id, tags.name AS name, count(*) AS count"
    query << " FROM taggings, tags, todos"
    query << " WHERE tags.id = tag_id"
    query << " AND todos.user_id=? "
    query << " AND taggings.taggable_type='Todo' "
    query << " AND taggings.taggable_id=todos.id "
    query << " AND (todos.created_at > ? OR "
    query << "      todos.completed_at > ?) "
    query << " GROUP BY tags.id, tags.name"
    query << " ORDER BY count DESC, name"
    query << " LIMIT 100"
    @tags_for_cloud_90days = Tag.find_by_sql(
      [query, current_user.id, @cut_off_3months, @cut_off_3months]
    ).sort_by { |tag| tag.name.downcase }

    max_90days, @tags_min_90days = 0, 0
    @tags_for_cloud_90days.each { |t|
      max_90days = [t.count.to_i, max_90days].max
      @tags_min_90days = [t.count.to_i, @tags_min_90days].min
    }

    @tags_divisor_90days = ((max_90days - @tags_min_90days) / levels) + 1
  end
end