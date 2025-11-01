SELECT
  discharge_outcome,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_10_days
FROM (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'death'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
      ELSE 'facility'
    END AS discharge_outcome,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 86 AND 96
) subquery
GROUP BY discharge_outcome;