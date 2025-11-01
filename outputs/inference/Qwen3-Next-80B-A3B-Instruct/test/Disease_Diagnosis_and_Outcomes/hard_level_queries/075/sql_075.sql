WITH full_risk AS (
  SELECT predicted_mortality
  FROM ... full cohort
),
ich_median AS (
  SELECT PERCENTILE_CONT(median_risk, 0.5) AS ich_median_risk FROM ich...
),
non_ich_median AS ( ... )
SELECT
  ich_median_risk,
  (SELECT PERCENTILE_CONT(predicted_mortality, 0.5) FROM full_risk) AS full_median,
  (SELECT COUNT(*) FROM full_risk WHERE predicted_mortality <= ich_median_risk) * 100.0 / COUNT(*) FROM full_risk AS ich_percentile;