WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.insurance,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.insurance LIKE '%MEDICARE%'
    AND UPPER(a.admission_type) = 'URGENT'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 OR UPPER(discharge_location) LIKE '%DIED%' THEN 'Death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS outcome
  FROM cohort
)
SELECT
  outcome,
  COUNT(*) AS n_patients,
  ROUND(AVG(los),2) AS mean_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)],2) AS median_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(75)],2) AS p75_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(90)],2) AS p90_los,
  ROUND(100 * SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_los_le_10
FROM categorized
GROUP BY outcome
ORDER BY outcome;