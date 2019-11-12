# Chicago Taxi and Ridehailing Dashboard API

A Rails API to serve as the backend for this dashboard: [Taxi and Ridehailing Usage in Chicago](https://toddwschneider.com/dashboards/chicago-taxi-ridehailing-data/)

The app queries and stores data from two relevant datasets on Chicago's open data portal:

1. [Taxi trips](https://data.cityofchicago.org/Transportation/Taxi-Trips/wrvz-psew)
2. [Transportation Network Providers trips](https://data.cityofchicago.org/Transportation/Transportation-Network-Providers-Trips/m6dm-c72p)

Taxi data is available since 1/1/2013, TNP data since 11/1/2018. As of 2019 there are three licensed TNPs in Chicago: Uber, Lyft, and Via. The TNP dataset does not identify which company provided each trip

The datasets are both made up of individual trips. The app executes [Socrata SoQL](https://dev.socrata.com/docs/queries/) queries against the raw datasets to produce monthly summaries, then stores those monthly summaries in the `chicago_monthly_reports` table. In theory, the dashboard could connect directly to the Socrata open data portal and run the queries on every page load, but that would be wildly impractical as it takes a few hours of query time to populate the full historical summaries

Most of the relevant code lives in `app/models/chicago_monthly_report.rb`

## Getting started

Prerequisites: [Ruby](https://www.ruby-lang.org/) and [PostgreSQL](https://www.postgresql.org)

Run the following commands to create the database and populate it with all months of available data:

```ruby
bundle exec rake db:setup
bundle exec rake jobs:work
```

Note that the initial database backfill will take several hours. You can tinker with `db/seeds.rb` before running the setup commands to, e.g., populate fewer months historically

## Keeping the database updated

`clock.rb` is configured to check the portal once per day and, if there are new months available, run the relevant queries to populate the database. You'll need to run both the clock and worker processes, e.g. on Heroku that would be one `clock` dyno and one `worker` dyno

## See also

- [chicago-taxi-data](https://github.com/toddwschneider/chicago-taxi-data) repo: similar to this dashboard repo, but instead of populating a table of monthly summaries, populates a local PostgreSQL database with all individual taxi and TNP trip records
- [nyc-taxi-data](https://github.com/toddwschneider/nyc-taxi-data) repo: download and import all of the publicly available NYC taxi and for-hire vehicle trip records
- [Taxi and Ridehailing Usage in New York City](https://toddwschneider.com/dashboards/nyc-taxi-ridehailing-uber-lyft-data/) dashboard

## Questions/issues/contact

todd@toddwschneider.com, or open a GitHub issue
