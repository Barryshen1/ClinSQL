WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.gender,
    p.anchor_age,
    a.discharge_location,
    a.hospital_expire_flag,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.subject_id = a.subject_id
   AND icu.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
),
classified AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      WHEN UPPER(discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      ELSE NULL
    END AS discharge_outcome
  FROM cohort
)
SELECT
  discharge_outcome,
  COUNT(*) AS n,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los, 2)[OFFSET(1)], 2) AS median_los,
  ROUND(100.0 * SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_le_10_days
FROM classified
WHERE discharge_outcome IS NOT NULL
GROUP BY discharge_outcome
ORDER BY discharge_outcome;