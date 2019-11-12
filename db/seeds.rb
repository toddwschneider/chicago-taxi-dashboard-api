taxi_start_month = Date.new(2013, 1, 1)
tnp_start_month = Date.new(2018, 11, 1)

taxi_end_month = ChicagoMonthlyReport.most_recent_month_available(resource: :taxi)
tnp_end_month = ChicagoMonthlyReport.most_recent_month_available(resource: :tnp)

month = taxi_start_month
while month <= taxi_end_month
  ChicagoMonthlyReport.update_all_taxi_reports_for_month(month: month)
  month += 1.month
end

month = tnp_start_month
while month <= tnp_end_month
  ChicagoMonthlyReport.update_all_tnp_reports_for_month(month: month)
  month += 1.month
end
