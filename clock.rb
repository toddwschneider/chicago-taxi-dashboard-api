require './config/boot'
require './config/environment'

require 'clockwork'
include Clockwork

every(1.day, 'check for new data', at: '07:00', tz: 'UTC') do
  ChicagoMonthlyReport.check_for_new_taxi_data
  ChicagoMonthlyReport.check_for_new_tnp_data
end
