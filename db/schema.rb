# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_12_224713) do
  create_table "fixtures", force: :cascade do |t|
    t.integer "away_score"
    t.integer "away_team_id", null: false
    t.datetime "created_at", null: false
    t.integer "home_score"
    t.integer "home_team_id", null: false
    t.datetime "kickoff_at", null: false
    t.integer "stadium_id", null: false
    t.integer "stage", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["away_team_id"], name: "index_fixtures_on_away_team_id"
    t.index ["home_team_id"], name: "index_fixtures_on_home_team_id"
    t.index ["kickoff_at"], name: "index_fixtures_on_kickoff_at"
    t.index ["stadium_id"], name: "index_fixtures_on_stadium_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "stadia", force: :cascade do |t|
    t.string "city", null: false
    t.string "country", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "teams", force: :cascade do |t|
    t.string "code", null: false
    t.string "confederation"
    t.datetime "created_at", null: false
    t.string "flag_emoji"
    t.string "group_name", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_teams_on_code", unique: true
    t.index ["group_name"], name: "index_teams_on_group_name"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "name", default: "", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "fixtures", "stadia"
  add_foreign_key "fixtures", "teams", column: "away_team_id"
  add_foreign_key "fixtures", "teams", column: "home_team_id"
  add_foreign_key "sessions", "users"
end
