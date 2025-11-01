WITH icu_hadm AS (
  -- all hospital admissions that had at least one ICU stay
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- LOS in days as fractional number
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN UPPER(COALESCE(a.discharge_location, '')) LIKE '%HOME%' THEN 'home'
      ELSE 'facility'
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN icu_hadm i USING (hadm_id)                      -- only admissions with ICU stay(s)
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
)

SELECT
  discharge_category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND((APPROX_QUANTILES(los_days, 100))[OFFSET(50)], 2) AS p50_los_days,
  ROUND((APPROX_QUANTILES(los_days, 100))[OFFSET(75)], 2) AS p75_los_days,
  ROUND((APPROX_QUANTILES(los_days, 100))[OFFSET(90)], 2) AS p90_los_days
FROM cohort
GROUP BY discharge_category
ORDER BY discharge_category;