WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 43 AND 53
    AND a.admission_location IN ('EMERGENCY ROOM', 'EMERGENCY ROOM ADMIT')
    AND a.dischtime IS NOT NULL
),
outcome_groups AS (
  SELECT
    hadm_id,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'death'
      WHEN discharge_location = 'HOME' THEN 'home'
      ELSE 'facility'
    END AS outcome
  FROM filtered_admissions
)
SELECT
  outcome,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] - APPROX_QUANTILES(los, 100)[OFFSET(25)] AS iqr,
  (COUNTIF(los <= 14) * 100.0) / COUNT(*) AS percentile_rank_14
FROM outcome_groups
GROUP BY outcome
ORDER BY outcome;