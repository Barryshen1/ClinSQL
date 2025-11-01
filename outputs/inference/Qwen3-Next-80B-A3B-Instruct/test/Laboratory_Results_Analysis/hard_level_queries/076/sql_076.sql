SELECT PERCENTILE_CONT(lab_instability_score, 0.95) AS p95_lab_score
FROM lab_events_critical;