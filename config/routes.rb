Rails.application.routes.draw do
  get '/chicago_dashboard_data', to: 'dashboards#chicago_dashboard_data'
end
