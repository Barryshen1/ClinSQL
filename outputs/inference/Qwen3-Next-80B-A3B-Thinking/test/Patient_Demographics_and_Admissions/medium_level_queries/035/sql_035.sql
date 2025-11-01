WITH admissions_data AS (
  SELECT
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    AND a.admission_location LIKE 'EMERGENCY%'
    AND a.dischtime IS NOT NULL
)
SELECT
  CASE
    WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOSPICE') THEN 'home'
    WHEN discharge_location = 'DEATH' THEN 'death'
    ELSE 'facility'
  END AS discharge_outcome,
  PERCENTILE_CONT(los, 0.5) WITHIN GROUP (ORDER BY los) AS median_los,
  PERCENTILE_CONT(los, 0.75) WITHIN GROUP (ORDER BY los) - PERCENTILE_CONT(los, 0.25) WITHIN GROUP (ORDER BY los) AS iqr_los,
  (COUNTIF(los <= 14) * 100.0) / COUNT(*) AS percentile_rank_14
FROM admissions_data
GROUP BY discharge_outcome;