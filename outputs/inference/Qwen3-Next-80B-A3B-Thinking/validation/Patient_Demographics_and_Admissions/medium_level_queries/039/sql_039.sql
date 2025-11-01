SELECT
  discharge_outcome,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75,
  (COUNTIF(los <= 7) * 100.0 / COUNT(*)) AS percentile_rank_7_days
FROM (
  SELECT
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location IN ('Home', 'Home Health Care') THEN 'home'
      ELSE 'facility'
    END AS discharge_outcome
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type IN ('Emergency', 'Urgent')
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
) AS subquery
GROUP BY discharge_outcome;