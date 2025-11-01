WITH filtered_admissions AS (
  SELECT 
    admissions.subject_id,
    admissions.hadm_id,
    admissions.admittime,
    admissions.dischtime,
    admissions.discharge_location,
    admissions.hospital_expire_flag,
    patients.anchor_age,
    patients.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
    ON admissions.subject_id = patients.subject_id
  WHERE 
    patients.gender = 'F'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
      WHERE icustays.subject_id = admissions.subject_id
        AND icustays.hadm_id = admissions.hadm_id
    )
),
with_outcome AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
      WHEN discharge_location LIKE 'HOSPICE%' THEN 'hospice'
      ELSE 'other'
    END AS outcome,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM filtered_admissions
  WHERE 
    (anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)) BETWEEN 63 AND 73
)
SELECT 
  outcome,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  COUNTIF(los_days <= 10.0) AS n_leq_10,
  (COUNTIF(los_days <= 10.0) / COUNT(*)) * 100 AS percent_leq_10
FROM with_outcome
WHERE outcome IN ('in-hospital death', 'home', 'hospice')
GROUP BY outcome
ORDER BY outcome;