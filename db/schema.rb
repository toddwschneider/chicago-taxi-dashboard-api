# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2019_11_10_221103) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "chicago_monthly_reports", force: :cascade do |t|
    t.text "trip_type", null: false
    t.date "month", null: false
    t.integer "trips"
    t.integer "unique_vehicles"
    t.integer "avg_unique_vehicles_per_day"
    t.float "avg_days_active_per_vehicle"
    t.integer "shared_trips_authorized"
    t.integer "shared_trips"
    t.float "avg_trip_seconds"
    t.float "avg_trip_miles"
    t.float "avg_fare"
    t.float "avg_cash_total_ex_tip"
    t.float "avg_credit_card_total_ex_tip"
    t.float "avg_credit_card_tip"
    t.float "frac_paid_with_credit_card"
    t.float "credit_card_frac_with_tip"
    t.float "avg_tolls"
    t.float "avg_extras"
    t.float "avg_additional_charges"
    t.float "avg_trip_total"
    t.integer "trips_with_valid_time_distance_fare"
    t.integer "pickups_within_2_miles_of_loop"
    t.integer "pickups_2_to_5_miles_from_loop"
    t.integer "pickups_over_5_miles_from_loop_ex_airports"
    t.integer "airports_pickups"
    t.integer "unknown_geo_pickups"
    t.float "weekday_afternoon_nns_to_lv_avg_miles"
    t.float "weekday_afternoon_nns_to_lv_avg_seconds"
    t.float "weekday_afternoon_nns_to_lv_avg_trip_total_ex_tip"
    t.integer "weekday_afternoon_nns_to_lv_valid_trips"
    t.float "weekday_afternoon_loop_to_ohare_avg_miles"
    t.float "weekday_afternoon_loop_to_ohare_avg_seconds"
    t.float "weekday_afternoon_loop_to_ohare_avg_trip_total_ex_tip"
    t.integer "weekday_afternoon_loop_to_ohare_valid_trips"
    t.integer "days_counted"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["month"], name: "index_chicago_monthly_reports_on_month"
    t.index ["trip_type", "month"], name: "index_chicago_monthly_reports_on_trip_type_and_month", unique: true
  end

  create_table "delayed_jobs", force: :cascade do |t|
    t.integer "priority", default: 0, null: false
    t.integer "attempts", default: 0, null: false
    t.text "handler", null: false
    t.text "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string "locked_by"
    t.string "queue"
    t.datetime "created_at", precision: 6
    t.datetime "updated_at", precision: 6
    t.index ["priority", "run_at"], name: "delayed_jobs_priority"
  end

end
