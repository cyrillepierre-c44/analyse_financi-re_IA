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

ActiveRecord::Schema[8.1].define(version: 2026_05_12_134921) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "balance_sheets", force: :cascade do |t|
    t.decimal "cash_and_equivalents", precision: 20, scale: 2
    t.datetime "created_at", null: false
    t.decimal "customer_advances_paid", precision: 20, scale: 2
    t.decimal "customer_advances_received", precision: 20, scale: 2
    t.decimal "deferred_income", precision: 20, scale: 2
    t.decimal "discounted_bills_not_due", precision: 20, scale: 2
    t.decimal "equity_method_investments", precision: 20, scale: 2
    t.decimal "finance_lease_debt", precision: 20, scale: 2
    t.decimal "financial_assets_gross", precision: 20, scale: 2
    t.decimal "financial_assets_net", precision: 20, scale: 2
    t.integer "financial_report_id", null: false
    t.decimal "finished_goods_inventory", precision: 20, scale: 2
    t.decimal "goodwill", precision: 20, scale: 2
    t.decimal "intangible_assets_gross", precision: 20, scale: 2
    t.decimal "intangible_assets_net", precision: 20, scale: 2
    t.decimal "lt_financial_debt", precision: 20, scale: 2
    t.decimal "merchandise_inventory", precision: 20, scale: 2
    t.decimal "minority_interests", precision: 20, scale: 2
    t.decimal "net_income_period", precision: 20, scale: 2
    t.decimal "other_operating_liabilities", precision: 20, scale: 2
    t.decimal "other_operating_receivables", precision: 20, scale: 2
    t.decimal "prepaid_expenses", precision: 20, scale: 2
    t.decimal "provisions_for_risks", precision: 20, scale: 2
    t.decimal "raw_materials_inventory", precision: 20, scale: 2
    t.decimal "reserves", precision: 20, scale: 2
    t.decimal "retained_earnings_bf", precision: 20, scale: 2
    t.decimal "share_capital", precision: 20, scale: 2
    t.decimal "share_premium", precision: 20, scale: 2
    t.decimal "short_term_investments", precision: 20, scale: 2
    t.decimal "st_financial_debt", precision: 20, scale: 2
    t.decimal "tangible_assets_gross", precision: 20, scale: 2
    t.decimal "tangible_assets_net", precision: 20, scale: 2
    t.decimal "tax_and_social_liabilities", precision: 20, scale: 2
    t.decimal "total_assets", precision: 20, scale: 2
    t.decimal "total_current_assets", precision: 20, scale: 2
    t.decimal "total_equity", precision: 20, scale: 2
    t.decimal "total_equity_and_liabilities", precision: 20, scale: 2
    t.decimal "total_fixed_assets_gross", precision: 20, scale: 2
    t.decimal "total_fixed_assets_net", precision: 20, scale: 2
    t.decimal "total_inventory", precision: 20, scale: 2
    t.decimal "total_liabilities", precision: 20, scale: 2
    t.decimal "trade_payables", precision: 20, scale: 2
    t.decimal "trade_receivables", precision: 20, scale: 2
    t.datetime "updated_at", null: false
    t.decimal "wip_inventory", precision: 20, scale: 2
    t.index ["financial_report_id"], name: "index_balance_sheets_on_financial_report_id", unique: true
  end

  create_table "cash_flow_statements", force: :cascade do |t|
    t.decimal "asset_disposals", precision: 20, scale: 2
    t.decimal "asset_impairment", precision: 20, scale: 2
    t.decimal "capital_expenditure", precision: 20, scale: 2
    t.decimal "capital_increase", precision: 20, scale: 2
    t.datetime "created_at", null: false
    t.decimal "depreciation_amortization", precision: 20, scale: 2
    t.decimal "dividends_paid", precision: 20, scale: 2
    t.integer "financial_report_id", null: false
    t.decimal "free_cash_flow", precision: 20, scale: 2
    t.decimal "gains_losses_on_disposals", precision: 20, scale: 2
    t.decimal "inventory_variation", precision: 20, scale: 2
    t.decimal "investing_cash_flow", precision: 20, scale: 2
    t.decimal "net_debt_change", precision: 20, scale: 2
    t.decimal "net_debt_closing", precision: 20, scale: 2
    t.decimal "net_debt_opening", precision: 20, scale: 2
    t.decimal "net_income", precision: 20, scale: 2
    t.decimal "operating_cash_flow", precision: 20, scale: 2
    t.decimal "other_wcr_variation", precision: 20, scale: 2
    t.decimal "provisions_variation", precision: 20, scale: 2
    t.decimal "self_financing_capacity", precision: 20, scale: 2
    t.decimal "total_wcr_variation", precision: 20, scale: 2
    t.decimal "trade_payables_variation", precision: 20, scale: 2
    t.decimal "trade_receivables_variation", precision: 20, scale: 2
    t.datetime "updated_at", null: false
    t.index ["financial_report_id"], name: "index_cash_flow_statements_on_financial_report_id", unique: true
  end

  create_table "companies", force: :cascade do |t|
    t.integer "accounting_standard", default: 0, null: false
    t.text "ai_analysis"
    t.datetime "ai_analyzed_at"
    t.string "country", default: "France", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "EUR", null: false
    t.integer "fiscal_year_end_month", default: 12, null: false
    t.text "ia_context"
    t.text "ia_context_gaps"
    t.string "ia_context_status", default: "pending"
    t.boolean "is_consolidated", default: false, null: false
    t.string "name", null: false
    t.string "sector"
    t.string "siren"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_companies_on_name"
    t.index ["siren"], name: "index_companies_on_siren", unique: true, where: "(siren IS NOT NULL)"
  end

  create_table "company_answers", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.datetime "generated_at"
    t.bigint "question_id", null: false
    t.json "selected_options", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "question_id"], name: "index_company_answers_on_company_id_and_question_id", unique: true
    t.index ["company_id"], name: "index_company_answers_on_company_id"
    t.index ["question_id"], name: "index_company_answers_on_question_id"
  end

  create_table "company_documents", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.string "document_type", default: "supplementary", null: false
    t.text "extracted_text"
    t.string "original_filename"
    t.text "processing_notes"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "status"], name: "index_company_documents_on_company_id_and_status"
    t.index ["company_id"], name: "index_company_documents_on_company_id"
  end

  create_table "cost_structures", force: :cascade do |t|
    t.integer "cost_category", null: false
    t.datetime "created_at", null: false
    t.integer "financial_report_id", null: false
    t.decimal "fixed_costs", precision: 20, scale: 2
    t.datetime "updated_at", null: false
    t.decimal "variable_costs", precision: 20, scale: 2
    t.index ["financial_report_id", "cost_category"], name: "index_cost_structures_on_financial_report_id_and_cost_category", unique: true
    t.index ["financial_report_id"], name: "index_cost_structures_on_financial_report_id"
  end

  create_table "financial_reports", force: :cascade do |t|
    t.integer "accounting_standard", default: 0, null: false
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.integer "fiscal_year", null: false
    t.integer "income_format", default: 0, null: false
    t.boolean "is_consolidated", default: false, null: false
    t.text "notes"
    t.date "period_end_date", null: false
    t.integer "period_type", default: 0, null: false
    t.string "source_file"
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year"], name: "index_financial_reports_on_company_id_and_fiscal_year", unique: true
    t.index ["company_id"], name: "index_financial_reports_on_company_id"
    t.index ["fiscal_year"], name: "index_financial_reports_on_fiscal_year"
  end

  create_table "income_statements", force: :cascade do |t|
    t.decimal "administrative_costs", precision: 20, scale: 2
    t.decimal "asset_impairment", precision: 20, scale: 2
    t.decimal "capitalized_production", precision: 20, scale: 2
    t.decimal "commercial_margin", precision: 20, scale: 2
    t.decimal "cost_of_sales", precision: 20, scale: 2
    t.datetime "created_at", null: false
    t.decimal "current_result", precision: 20, scale: 2
    t.decimal "depreciation_amortization", precision: 20, scale: 2
    t.decimal "distribution_marketing_costs", precision: 20, scale: 2
    t.decimal "dividends_paid", precision: 20, scale: 2
    t.decimal "ebit", precision: 20, scale: 2
    t.decimal "ebitda", precision: 20, scale: 2
    t.decimal "exceptional_expenses", precision: 20, scale: 2
    t.decimal "exceptional_income", precision: 20, scale: 2
    t.decimal "financial_expenses", precision: 20, scale: 2
    t.decimal "financial_income", precision: 20, scale: 2
    t.integer "financial_report_id", null: false
    t.decimal "gross_margin", precision: 20, scale: 2
    t.decimal "income_tax", precision: 20, scale: 2
    t.decimal "merchandise_purchases", precision: 20, scale: 2
    t.decimal "merchandise_sales", precision: 20, scale: 2
    t.decimal "merchandise_stock_variation", precision: 20, scale: 2
    t.decimal "minority_interests", precision: 20, scale: 2
    t.decimal "net_income", precision: 20, scale: 2
    t.decimal "operating_subsidies", precision: 20, scale: 2
    t.decimal "other_external_expenses", precision: 20, scale: 2
    t.decimal "other_operating_expenses", precision: 20, scale: 2
    t.decimal "other_operating_income", precision: 20, scale: 2
    t.decimal "personnel_expenses", precision: 20, scale: 2
    t.decimal "production_sold", precision: 20, scale: 2
    t.decimal "production_stored", precision: 20, scale: 2
    t.decimal "provisions_charge", precision: 20, scale: 2
    t.decimal "raw_materials_purchases", precision: 20, scale: 2
    t.decimal "raw_materials_stock_variation", precision: 20, scale: 2
    t.decimal "retained_earnings", precision: 20, scale: 2
    t.decimal "revenue", precision: 20, scale: 2
    t.decimal "taxes_and_duties", precision: 20, scale: 2
    t.datetime "updated_at", null: false
    t.decimal "value_added", precision: 20, scale: 2
    t.index ["financial_report_id"], name: "index_income_statements_on_financial_report_id", unique: true
  end

  create_table "questions", force: :cascade do |t|
    t.string "answer_type", default: "single", null: false
    t.datetime "created_at", null: false
    t.json "options", default: [], null: false
    t.integer "position", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_questions_on_position"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "balance_sheets", "financial_reports"
  add_foreign_key "cash_flow_statements", "financial_reports"
  add_foreign_key "company_answers", "companies"
  add_foreign_key "company_answers", "questions"
  add_foreign_key "company_documents", "companies"
  add_foreign_key "cost_structures", "financial_reports"
  add_foreign_key "financial_reports", "companies"
  add_foreign_key "income_statements", "financial_reports"
end
