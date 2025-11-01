WITH icu_hadms AS (
  -- distinct hospital admissions that have at least one ICU stay
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

eligible_admissions AS (
  -- female patients age 63-73 with a hospital admission that had an ICU stay
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- LOS in days as a decimal
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN icu_hadms i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.dischtime IS NOT NULL
)

SELECT
  outcome,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND((APPROX_QUANTILES(los_days, 2)[OFFSET(1)]), 2) AS median_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_le_10_days
FROM (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Other'
    END AS outcome
  FROM eligible_admissions
)
WHERE outcome IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY outcome
ORDER BY outcome;