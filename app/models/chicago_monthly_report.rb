class ChicagoMonthlyReport < ApplicationRecord
  API_BASE_URL = "https://data.cityofchicago.org/resource/"
  RESOURCE_IDS = {taxi: "wrvz-psew", tnp: "m6dm-c72p"}
  TAXI_TRIP_TYPES = %w(taxi)
  TNP_TRIP_TYPES = %w(tnp tnp_not_shared tnp_unmatched_share_request tnp_shared)
  TNP_SHARED_RIDE_CONDITIONS = {
    not_shared: "shared_trip_authorized = false",
    unmatched_share_request: "shared_trip_authorized = true AND trips_pooled = 1",
    shared: "shared_trip_authorized = true AND trips_pooled > 1"
  }
  DASHBOARD_START_DATE = Date.new(2014, 1, 1)

  validates_presence_of :month, :trip_type
  validates_uniqueness_of :month, scope: :trip_type
  validates_inclusion_of :trip_type, in: (TAXI_TRIP_TYPES | TNP_TRIP_TYPES)

  scope :taxi, -> { where(trip_type: TAXI_TRIP_TYPES) }
  scope :tnp, -> { where(trip_type: TNP_TRIP_TYPES) }

  class << self
    def update_all_taxi_reports_for_month(month:)
      date_lower = month.to_date.beginning_of_month
      date_upper = date_lower.end_of_month + 1.day
      opts = {date_lower: date_lower, date_upper: date_upper}

      %i(
        taxi_trips
        taxi_unique_vehicles
        taxi_unique_vehicles_per_day
        taxi_avg_time_distance_fare
        taxi_pickups_by_geo
        taxi_weekday_afternoon_loop_to_ohare
        taxi_weekday_afternoon_nns_to_lv
      ).each do |method_name|
        update_single_report_query(
          month: month,
          method_name: method_name,
          opts: opts
        )
      end
    end
    handle_asynchronously :update_all_taxi_reports_for_month

    def update_all_tnp_reports_for_month(month:)
      date_lower = month.to_date.beginning_of_month
      date_upper = date_lower.end_of_month + 1.day
      opts = {date_lower: date_lower, date_upper: date_upper}

      method_names = %i(
        tnp_trips
        tnp_avg_time_distance_fare
        tnp_pickups_by_geo
        tnp_weekday_afternoon_loop_to_ohare
        tnp_weekday_afternoon_nns_to_lv
      )

      shared_statuses = [nil] + TNP_SHARED_RIDE_CONDITIONS.keys

      method_names.product(shared_statuses).each do |method_name, shared_status|
        update_single_report_query(
          month: month,
          method_name: method_name,
          opts: opts.merge(shared_status: shared_status)
        )
      end
    end
    handle_asynchronously :update_all_tnp_reports_for_month

    def update_single_report_query(month:, method_name:, opts:)
      results = send(method_name, opts)
      update_reports_from_query_results(results)
    end
    handle_asynchronously :update_single_report_query

    def check_for_new_taxi_data
      current_month = taxi.maximum(:month) + 1.month
      most_recent_available = most_recent_month_available(resource: :taxi)

      while current_month <= most_recent_available
        update_all_taxi_reports_for_month(month: current_month)
        current_month += 1.month
      end
    end
    handle_asynchronously :check_for_new_taxi_data

    def check_for_new_tnp_data
      current_month = tnp.maximum(:month) + 1.month
      most_recent_available = most_recent_month_available(resource: :tnp)

      while current_month <= most_recent_available
        update_all_tnp_reports_for_month(month: current_month)
        current_month += 1.month
      end
    end
    handle_asynchronously :check_for_new_tnp_data
  end

  def self.update_reports_from_query_results(query_results)
    trip_type = [
      query_results.fetch(:resource),
      query_results.fetch(:shared_status)
    ].compact.join("_")

    query_results.fetch(:data).each do |row|
      month = Time.zone.parse(row.fetch(:month)).to_date.end_of_month
      report = find_or_initialize_by(month: month, trip_type: trip_type)

      row.except(:month).each do |k, v|
        report[k] = v if report.has_attribute?(k)
      end

      report.save!
    end
  end

  def self.most_recent_trip_start(resource:)
    sql = <<-SQL
      SELECT trip_start_timestamp
      ORDER BY trip_start_timestamp DESC
      LIMIT 1
    SQL

    rows = socrata_query(sql: sql, resource: resource).fetch(:data)

    Date.parse(rows.first.fetch(:trip_start_timestamp))
  end

  def self.most_recent_month_available(resource:)
    date = most_recent_trip_start(resource: resource)
    date == date.end_of_month ? date : (date - 1.month).end_of_month
  end

  def self.taxi_trips(date_lower:, date_upper:)
    sql = <<-SQL
      SELECT
        date_trunc_ym(trip_start_timestamp) AS month,
        count(*) AS trips
      WHERE trip_start_timestamp >= #{connection.quote(date_lower)}
        AND trip_start_timestamp < #{connection.quote(date_upper)}
      GROUP BY month
      ORDER BY month
    SQL

    socrata_query(sql: sql, resource: :taxi)
  end

  def self.append_tnp_shared_conditions(shared_status: nil)
    return unless shared_status
    " AND (#{TNP_SHARED_RIDE_CONDITIONS.fetch(shared_status.to_sym)}) "
  end

  def self.tnp_trips(date_lower:, date_upper:, shared_status: nil)
    sql = <<-SQL
      SELECT
        date_trunc_ym(trip_start_timestamp) AS month,
        count(*) AS trips,
        sum(case(shared_trip_authorized = true, 1)) AS shared_trips_authorized,
        sum(case(shared_trip_authorized = true AND trips_pooled > 1, 1)) AS shared_trips
      WHERE trip_start_timestamp >= #{connection.quote(date_lower)}
        AND trip_start_timestamp < #{connection.quote(date_upper)}
        #{append_tnp_shared_conditions(shared_status: shared_status)}
      GROUP BY month
      ORDER BY month
    SQL

    socrata_query(sql: sql, resource: :tnp, shared_status: shared_status)
  end

  def self.taxi_unique_vehicles(date_lower:, date_upper:)
    sql = <<-SQL
      SELECT DISTINCT
        date_trunc_ym(trip_start_timestamp) AS month,
        date_trunc_ymd(trip_start_timestamp) AS day,
        taxi_id
      WHERE trip_start_timestamp >= #{connection.quote(date_lower)}
        AND trip_start_timestamp < #{connection.quote(date_upper)}

      |>

      SELECT
        month,
        taxi_id,
        count(*) AS days_active
      GROUP BY month, taxi_id

      |>

      SELECT
        month,
        avg(days_active) AS avg_days_active_per_vehicle,
        count(*) AS unique_vehicles
      GROUP BY month
      ORDER BY month
    SQL

    socrata_query(sql: sql, resource: :taxi)
  end

  def self.taxi_unique_vehicles_per_day(date_lower:, date_upper:)
    sql = <<-SQL
      SELECT DISTINCT
        date_trunc_ym(trip_start_timestamp) AS month,
        date_trunc_ymd(trip_start_timestamp) AS day,
        taxi_id
      WHERE trip_start_timestamp >= #{connection.quote(date_lower)}
        AND trip_start_timestamp < #{connection.quote(date_upper)}

      |>

      SELECT
        month,
        day,
        count(*) AS unique_vehicles
      GROUP BY month, day

      |>

      SELECT
        month,
        avg(unique_vehicles) AS avg_unique_vehicles_per_day,
        count(*) AS days_counted
      GROUP BY month
      ORDER BY month
    SQL

    socrata_query(sql: sql, resource: :taxi)
  end

  def self.valid_time_distance_fare_conditions(resource:)
    tip_column = {taxi: "tips", tnp: "tip"}.fetch(resource.to_sym)

    <<-SQL
      trip_miles BETWEEN 0.1 AND 200
        AND trip_seconds BETWEEN 60 AND 3 * 60 * 60
        AND trip_miles / (trip_seconds / (60 * 60)) BETWEEN 0.5 AND 80
        AND fare BETWEEN 2 AND 1000
        AND (
          (fare - 3) / trip_miles BETWEEN 0.5 AND 25
          OR (fare - 3) / trip_seconds * 60 BETWEEN 0.2 AND 5
        )
        AND coalesce(#{tip_column}, 0) < 2 * fare
    SQL
  end

  # NB: don't calculate avg(trip_total) for taxis because it's misleading due
  # to cash fares excluding tips in trip_total
  def self.taxi_avg_time_distance_fare(date_lower:, date_upper:)
    sql = <<-SQL
      SELECT
        date_trunc_ym(trip_start_timestamp) AS month,
        avg(trip_miles) AS avg_trip_miles,
        avg(trip_seconds) AS avg_trip_seconds,
        avg(fare) AS avg_fare,
        avg(case(lower(payment_type) == 'cash', fare + coalesce(tolls, 0) + coalesce(extras, 0))) as avg_cash_total_ex_tip,
        avg(case(lower(payment_type) in ('credit card', 'mobile'), fare + coalesce(tolls, 0) + coalesce(extras, 0))) as avg_credit_card_total_ex_tip,
        avg(case(lower(payment_type) in ('credit card', 'mobile'), tips)) as avg_credit_card_tip,
        avg(case(
          lower(payment_type) in ('credit card', 'mobile'), 1,
          lower(payment_type) == 'cash', 0
        )) AS frac_paid_with_credit_card,
        avg(case(
          lower(payment_type) in ('credit card', 'mobile') AND coalesce(tips, 0) > 0, 1,
          lower(payment_type) in ('credit card', 'mobile'), 0
        )) AS credit_card_frac_with_tip,
        avg(coalesce(tolls, 0)) AS avg_tolls,
        avg(coalesce(extras, 0)) AS avg_extras,
        count(*) AS trips_with_valid_time_distance_fare
      WHERE trip_start_timestamp >= #{connection.quote(date_lower)}
        AND trip_start_timestamp < #{connection.quote(date_upper)}
        AND #{valid_time_distance_fare_conditions(resource: :taxi)}
      GROUP BY month
      ORDER BY month
    SQL

    socrata_query(sql: sql, resource: :taxi)
  end

  def self.tnp_avg_time_distance_fare(date_lower:, date_upper:, shared_status: nil)
    sql = <<-SQL
      SELECT
        date_trunc_ym(trip_start_timestamp) AS month,
        avg(trip_miles) AS avg_trip_miles,
        avg(trip_seconds) AS avg_trip_seconds,
        avg(fare) AS avg_fare,
        avg(coalesce(tip, 0)) as avg_credit_card_tip,
        avg(coalesce(additional_charges, 0)) AS avg_additional_charges,
        avg(trip_total) AS avg_trip_total,
        avg(case(coalesce(tip, 0) > 0, 1, true, 0)) AS credit_card_frac_with_tip,
        count(*) AS trips_with_valid_time_distance_fare
      WHERE trip_start_timestamp >= #{connection.quote(date_lower)}
        AND trip_start_timestamp < #{connection.quote(date_upper)}
        AND #{valid_time_distance_fare_conditions(resource: :tnp)}
        #{append_tnp_shared_conditions(shared_status: shared_status)}
      GROUP BY month
      ORDER BY month
    SQL

    socrata_query(sql: sql, resource: :tnp, shared_status: shared_status)
  end

  def self.pickups_by_geo(date_lower:, date_upper:, resource:, shared_status: nil)
    # NB airport pickups are not exact because O'Hare and Garfield Ridge
    # community areas include more than just airports
    within_2_miles_of_loop = [8, 28, 32, 33]
    within_2_to_5_miles_of_loop = [6, 7, 22, 24, 27, 29, 31, 34, 35, 36, 37, 38, 59, 60]
    airports = [56, 76]
    ids_to_exclude = within_2_miles_of_loop | within_2_to_5_miles_of_loop | airports

    sql = <<-SQL
      SELECT
        date_trunc_ym(trip_start_timestamp) AS month,
        sum(case(pickup_community_area IN (#{within_2_miles_of_loop.join(",")}), 1)) AS pickups_within_2_miles_of_loop,
        sum(case(pickup_community_area IN (#{within_2_to_5_miles_of_loop.join(",")}), 1)) AS pickups_2_to_5_miles_from_loop,
        sum(case(pickup_community_area NOT IN (#{ids_to_exclude.join(",")}), 1)) AS pickups_over_5_miles_from_loop_ex_airports,
        sum(case(pickup_community_area IN (#{airports.join(",")}), 1)) AS airports_pickups,
        sum(case(pickup_community_area IS NULL, 1)) as unknown_geo_pickups
      WHERE trip_start_timestamp >= #{connection.quote(date_lower)}
        AND trip_start_timestamp < #{connection.quote(date_upper)}
        #{append_tnp_shared_conditions(shared_status: shared_status)}
      GROUP BY month
      ORDER BY month
    SQL

    socrata_query(sql: sql, resource: resource, shared_status: shared_status)
  end

  def self.taxi_pickups_by_geo(date_lower:, date_upper:)
    pickups_by_geo(date_lower: date_lower, date_upper: date_upper, resource: :taxi)
  end

  def self.tnp_pickups_by_geo(date_lower:, date_upper:, shared_status: nil)
    pickups_by_geo(date_lower: date_lower, date_upper: date_upper, resource: :tnp, shared_status: shared_status)
  end

  # Near North Side to Lake View
  def self.weekday_afternoon_nns_to_lv(date_lower:, date_upper:, resource:, shared_status: nil)
    travel_times_between(
      date_lower: date_lower,
      date_upper: date_upper,
      resource: resource,
      shared_status: shared_status,
      pickup_community_areas: 8,
      dropoff_community_areas: 6,
      days_of_week: [1, 2, 3, 4, 5],
      hours_of_day: [16, 17, 18, 19],
      column_prefix: "weekday_afternoon_nns_to_lv_"
    )
  end

  def self.taxi_weekday_afternoon_nns_to_lv(date_lower:, date_upper:)
    weekday_afternoon_nns_to_lv(date_lower: date_lower, date_upper: date_upper, resource: :taxi)
  end

  def self.tnp_weekday_afternoon_nns_to_lv(date_lower:, date_upper:, shared_status: nil)
    weekday_afternoon_nns_to_lv(date_lower: date_lower, date_upper: date_upper, resource: :tnp, shared_status: shared_status)
  end

  def self.weekday_afternoon_loop_to_ohare(date_lower:, date_upper:, resource:, shared_status: nil)
    travel_times_between(
      date_lower: date_lower,
      date_upper: date_upper,
      resource: resource,
      shared_status: shared_status,
      pickup_community_areas: 32,
      dropoff_community_areas: 76,
      days_of_week: [1, 2, 3, 4, 5],
      hours_of_day: [15, 16, 17],
      column_prefix: "weekday_afternoon_loop_to_ohare_"
    )
  end

  def self.taxi_weekday_afternoon_loop_to_ohare(date_lower:, date_upper:)
    weekday_afternoon_loop_to_ohare(date_lower: date_lower, date_upper: date_upper, resource: :taxi)
  end

  def self.tnp_weekday_afternoon_loop_to_ohare(date_lower:, date_upper:, shared_status: nil)
    weekday_afternoon_loop_to_ohare(date_lower: date_lower, date_upper: date_upper, resource: :tnp, shared_status: shared_status)
  end

  def self.travel_times_between(
    date_lower:,
    date_upper:,
    resource:,
    shared_status: nil,
    pickup_community_areas:,
    dropoff_community_areas:,
    days_of_week: nil,
    hours_of_day: nil,
    column_prefix: nil
  )
    where_conditions = <<-SQL
      trip_start_timestamp >= #{connection.quote(date_lower)}
        AND trip_start_timestamp < #{connection.quote(date_upper)}
        AND pickup_community_area IN (#{quoted_array(pickup_community_areas)})
        AND dropoff_community_area IN (#{quoted_array(dropoff_community_areas)})
        AND #{valid_time_distance_fare_conditions(resource: resource)}
    SQL

    if days_of_week
      where_conditions << " AND date_extract_dow(trip_start_timestamp) IN (#{quoted_array(days_of_week)})"
    end

    if hours_of_day
      where_conditions << " AND date_extract_hh(trip_start_timestamp) IN (#{quoted_array(hours_of_day)})"
    end

    fare_calc = if resource.to_sym == :taxi
      "fare + coalesce(tolls, 0) + coalesce(extras, 0)"
    elsif resource.to_sym == :tnp
      "fare + coalesce(additional_charges, 0)"
    else
      raise "invalid resource"
    end

    sql = <<-SQL
      SELECT
        date_trunc_ym(trip_start_timestamp) AS month,
        avg(trip_miles) AS #{column_prefix}avg_miles,
        avg(trip_seconds) AS #{column_prefix}avg_seconds,
        avg(#{fare_calc}) AS #{column_prefix}avg_trip_total_ex_tip,
        count(*) AS #{column_prefix}valid_trips
      WHERE #{where_conditions}
        #{append_tnp_shared_conditions(shared_status: shared_status)}
      GROUP BY month
      ORDER BY month
    SQL

    socrata_query(sql: sql, resource: resource, shared_status: shared_status)
  end

  def self.taxi_dashboard_data
    select_fields = <<-SQL
      trip_type,
      month,
      round((trips / extract(day FROM month))::numeric) AS trips_per_day,
      unique_vehicles,
      round(trips::numeric / unique_vehicles) AS trips_per_vehicle,
      avg_unique_vehicles_per_day,
      round((trips / extract(day FROM month) / avg_unique_vehicles_per_day)::numeric, 1) AS trips_per_day_per_active_vehicle,
      round((avg_trip_seconds / 3600 * trips / extract(day FROM month) / avg_unique_vehicles_per_day)::numeric, 1) AS trip_in_progress_hours_per_day_per_active_vehicle,
      round(avg_days_active_per_vehicle::numeric, 1) AS avg_days_active_per_vehicle,
      round(avg_trip_seconds::numeric / 60, 1) AS avg_trip_minutes,
      round(avg_trip_miles::numeric, 2) AS avg_trip_miles,
      round((avg_trip_miles / avg_trip_seconds)::numeric * 3600, 1) AS avg_trip_mph,
      round(pickups_within_2_miles_of_loop::numeric / extract(day FROM month)) AS pickups_within_2_miles_of_loop,
      round(pickups_2_to_5_miles_from_loop::numeric / extract(day FROM month)) AS pickups_2_to_5_miles_from_loop,
      round(pickups_over_5_miles_from_loop_ex_airports::numeric / extract(day FROM month)) AS pickups_over_5_miles_from_loop_ex_airports,
      round(airports_pickups::numeric / extract(day FROM month)) AS airports_pickups,
      round(unknown_geo_pickups::numeric / extract(day FROM month)) AS unknown_geo_pickups,
      round(weekday_afternoon_nns_to_lv_avg_miles::numeric, 2) AS weekday_afternoon_nns_to_lv_avg_miles,
      round(weekday_afternoon_nns_to_lv_avg_seconds::numeric / 60, 1) AS weekday_afternoon_nns_to_lv_avg_minutes,
      round(weekday_afternoon_nns_to_lv_avg_trip_total_ex_tip::numeric, 2) AS weekday_afternoon_nns_to_lv_avg_trip_total_ex_tip,
      round((weekday_afternoon_nns_to_lv_valid_trips / extract(day FROM month))::numeric) AS weekday_afternoon_nns_to_lv_trips_per_day,
      round(weekday_afternoon_loop_to_ohare_avg_miles::numeric, 2) AS weekday_afternoon_loop_to_ohare_avg_miles,
      round(weekday_afternoon_loop_to_ohare_avg_seconds::numeric / 60, 1) AS weekday_afternoon_loop_to_ohare_avg_minutes,
      round(weekday_afternoon_loop_to_ohare_avg_trip_total_ex_tip::numeric, 2) AS weekday_afternoon_loop_to_ohare_avg_trip_total_ex_tip,
      round((weekday_afternoon_loop_to_ohare_valid_trips / extract(day FROM month))::numeric) AS weekday_afternoon_loop_to_ohare_trips_per_day,
      round(100 * ((CASE WHEN month >= '2017-01-01' THEN trips END)::numeric / lag(trips, 12) OVER (PARTITION BY trip_type ORDER BY month) - 1), 1) AS trips_growth_yoy,
      round((avg_fare + avg_tolls + avg_extras)::numeric, 2) AS avg_total_ex_tip,
      round(100 * (avg_credit_card_tip / avg_credit_card_total_ex_tip)::numeric, 1) AS avg_credit_card_tip_pct,
      round(100 * credit_card_frac_with_tip::numeric, 1) AS credit_card_pct_with_tip,
      round((trips * (avg_fare + avg_tolls + avg_extras) / extract(day FROM month))::numeric) AS estimated_daily_farebox,
      round((trips * (avg_fare + avg_tolls + avg_extras) / unique_vehicles)::numeric) AS estimated_monthly_farebox_per_vehicle,
      round((
        trips *
          (avg_fare + avg_tolls + avg_extras) /
          extract(day FROM month) /
          avg_unique_vehicles_per_day
      )::numeric) AS estimated_daily_farebox_per_active_vehicle,
      round(((avg_fare + avg_tolls + avg_extras) / avg_trip_seconds * 60)::numeric, 2) AS avg_farebox_per_minute,
      round(((avg_fare + avg_tolls + avg_extras) / avg_trip_miles)::numeric, 2) AS avg_farebox_per_mile,
      round(100 * trips_with_valid_time_distance_fare::numeric / trips, 1) AS pct_trips_with_valid_time_distance_fare
    SQL

    rows = taxi.
      select(select_fields).
      where("month >= ?", DASHBOARD_START_DATE).
      order(:trip_type, :month)

    date = rows.map(&:month).max.strftime("%b %-d, %Y")

    rows.group_by(&:trip_type).map do |trip_type, rows|
      fields = rows.first.attributes.except("id", "trip_type").keys

      data = rows.map do |row|
        row.attributes.values_at(*fields).map { |v| to_output_format(v) }
      end

      [
        trip_type.to_sym,
        fields.zip(data.transpose).to_h
      ]
    end.to_h.merge(taxi_date: date)
  end

  def self.tnp_dashboard_data
    select_fields = <<-SQL
      trip_type,
      month,
      round((trips / extract(day FROM month))::numeric) AS trips_per_day,
      round(avg_trip_seconds::numeric / 60, 1) AS avg_trip_minutes,
      round(avg_trip_miles::numeric, 2) AS avg_trip_miles,
      round((avg_trip_miles / avg_trip_seconds)::numeric * 3600, 1) AS avg_trip_mph,
      round(pickups_within_2_miles_of_loop::numeric / extract(day FROM month)) AS pickups_within_2_miles_of_loop,
      round(pickups_2_to_5_miles_from_loop::numeric / extract(day FROM month)) AS pickups_2_to_5_miles_from_loop,
      round(pickups_over_5_miles_from_loop_ex_airports::numeric / extract(day FROM month)) AS pickups_over_5_miles_from_loop_ex_airports,
      round(airports_pickups::numeric / extract(day FROM month)) AS airports_pickups,
      round(unknown_geo_pickups::numeric / extract(day FROM month)) AS unknown_geo_pickups,
      round(weekday_afternoon_nns_to_lv_avg_miles::numeric, 2) AS weekday_afternoon_nns_to_lv_avg_miles,
      round(weekday_afternoon_nns_to_lv_avg_seconds::numeric / 60, 1) AS weekday_afternoon_nns_to_lv_avg_minutes,
      round(weekday_afternoon_nns_to_lv_avg_trip_total_ex_tip::numeric, 2) AS weekday_afternoon_nns_to_lv_avg_trip_total_ex_tip,
      round((weekday_afternoon_nns_to_lv_valid_trips / extract(day FROM month))::numeric) AS weekday_afternoon_nns_to_lv_trips_per_day,
      round(weekday_afternoon_loop_to_ohare_avg_miles::numeric, 2) AS weekday_afternoon_loop_to_ohare_avg_miles,
      round(weekday_afternoon_loop_to_ohare_avg_seconds::numeric / 60, 1) AS weekday_afternoon_loop_to_ohare_avg_minutes,
      round(weekday_afternoon_loop_to_ohare_avg_trip_total_ex_tip::numeric, 2) AS weekday_afternoon_loop_to_ohare_avg_trip_total_ex_tip,
      round((weekday_afternoon_loop_to_ohare_valid_trips / extract(day FROM month))::numeric) AS weekday_afternoon_loop_to_ohare_trips_per_day,
      round((100.0 * trips / lag(trips, 12) OVER (PARTITION BY trip_type ORDER BY month))::numeric - 100, 1) AS trips_growth_yoy,
      round((avg_fare + avg_additional_charges)::numeric, 2) AS avg_total_ex_tip,
      round(100 * (avg_credit_card_tip / (avg_fare + avg_additional_charges))::numeric, 1) AS avg_credit_card_tip_pct,
      round(100 * credit_card_frac_with_tip::numeric, 1) AS credit_card_pct_with_tip,
      round(trips::numeric * (avg_fare + avg_additional_charges) / extract(day FROM month)) AS estimated_daily_farebox,
      round(((avg_fare + avg_additional_charges) / avg_trip_seconds * 60)::numeric, 2) AS avg_farebox_per_minute,
      round(((avg_fare + avg_additional_charges) / avg_trip_miles)::numeric, 2) AS avg_farebox_per_mile,
      round(100 * shared_trips::numeric / nullif(shared_trips_authorized, 0), 1) AS pct_share_requests_matched,
      round(100 * shared_trips_authorized::numeric / trips, 1) AS pct_trips_with_share_request,
      round(100 * trips_with_valid_time_distance_fare::numeric / trips, 1) AS pct_trips_with_valid_time_distance_fare
    SQL

    rows = tnp.
      select(select_fields).
      where("month >= ?", DASHBOARD_START_DATE).
      order(:trip_type, :month)

    date = rows.map(&:month).max.strftime("%b %-d, %Y")

    rows.group_by(&:trip_type).map do |trip_type, rows|
      fields = rows.first.attributes.except("id", "trip_type").keys

      data = rows.map do |row|
        row.attributes.values_at(*fields).map { |v| to_output_format(v) }
      end

      [
        trip_type.to_sym,
        fields.zip(data.transpose).to_h
      ]
    end.to_h.merge(tnp_date: date)
  end

  def self.dashboard_data
    taxi_dashboard_data.merge(tnp_dashboard_data)
  end

  def self.daily_trips(start_date:, end_date:, resource:)
    sql = <<-SQL
      SELECT
        date_trunc_ymd(trip_start_timestamp) AS date,
        count(*) AS trips
      WHERE trip_start_timestamp >= #{connection.quote(start_date)}
        AND trip_start_timestamp < #{connection.quote(end_date + 1.day)}
      GROUP BY date
      ORDER BY date
    SQL

    socrata_query(sql: sql, resource: resource)
  end

  private

  def self.socrata_query(sql:, resource:, shared_status: nil, timeout: 360)
    resource_id = RESOURCE_IDS.fetch(resource.to_sym)
    url_query = {"$query" => sql.squish}.to_query

    url = "#{API_BASE_URL}#{resource_id}.json?#{url_query}"
    response = RestClient::Request.execute(url: url, method: :get, timeout: timeout)
    json = JSON.parse(response.body)

    {
      resource: resource,
      shared_status: shared_status,
      data: json.map(&:with_indifferent_access)
    }
  end

  def self.quoted_array(values)
    Array.wrap(values).map { |v| connection.quote(v) }.join(",")
  end

  def self.to_output_format(value)
    return value.beginning_of_day.to_i * 1000 if value.is_a?(Date)
    return value unless value.is_a?(String)
    value.to_i == value.to_f ? value.to_i : value.to_f
  end
end
