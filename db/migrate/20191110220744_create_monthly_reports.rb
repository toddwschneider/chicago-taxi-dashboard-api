class CreateMonthlyReports < ActiveRecord::Migration[6.0]
  def change
    create_table :chicago_monthly_reports do |t|
      t.text :trip_type, null: false
      t.date :month, null: false

      t.integer :trips
      t.integer :unique_vehicles
      t.integer :avg_unique_vehicles_per_day
      t.float :avg_days_active_per_vehicle

      t.integer :shared_trips_authorized
      t.integer :shared_trips

      t.float :avg_trip_seconds
      t.float :avg_trip_miles
      t.float :avg_fare
      t.float :avg_cash_total_ex_tip
      t.float :avg_credit_card_total_ex_tip
      t.float :avg_credit_card_tip
      t.float :frac_paid_with_credit_card
      t.float :credit_card_frac_with_tip
      t.float :avg_tolls
      t.float :avg_extras
      t.float :avg_additional_charges
      t.float :avg_trip_total
      t.integer :trips_with_valid_time_distance_fare

      t.integer :pickups_within_2_miles_of_loop
      t.integer :pickups_2_to_5_miles_from_loop
      t.integer :pickups_over_5_miles_from_loop_ex_airports
      t.integer :airports_pickups
      t.integer :unknown_geo_pickups

      t.float :weekday_afternoon_nns_to_lv_avg_miles
      t.float :weekday_afternoon_nns_to_lv_avg_seconds
      t.float :weekday_afternoon_nns_to_lv_avg_trip_total_ex_tip
      t.integer :weekday_afternoon_nns_to_lv_valid_trips
      t.float :weekday_afternoon_loop_to_ohare_avg_miles
      t.float :weekday_afternoon_loop_to_ohare_avg_seconds
      t.float :weekday_afternoon_loop_to_ohare_avg_trip_total_ex_tip
      t.integer :weekday_afternoon_loop_to_ohare_valid_trips

      t.integer :days_counted
      t.timestamps
    end

    add_index :chicago_monthly_reports, %i(trip_type month), unique: true
    add_index :chicago_monthly_reports, :month
  end
end
