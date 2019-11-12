class DashboardsController < ApplicationController
  def chicago_dashboard_data
    render json: ChicagoMonthlyReport.dashboard_data
  end
end
