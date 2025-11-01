APPROX_QUANTILES(total_events, 10000)[OFFSET(7500)] AS target_75th_diagnostic_events
   APPROX_QUANTILES(total_events, 10000)[OFFSET(9500)] AS target_95th_diagnostic_events;