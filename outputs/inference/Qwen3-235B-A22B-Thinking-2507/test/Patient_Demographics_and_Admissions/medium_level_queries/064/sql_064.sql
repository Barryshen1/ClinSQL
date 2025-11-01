WITH base AS (
  SELECT 
    a.hadm_id,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS adm_year,
    a.dischtime,
    a.admittime,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS hospital_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
      WHERE i.hadm_id = a.hadm_id
    )
),
filtered AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location = 'HOSPICE' THEN 'hospice'
      ELSE NULL 
    END AS outcome
  FROM base
  WHERE age_at_admission BETWEEN 63 AND 73
)
SELECT 
  outcome,
  COUNT(*) AS n,
  AVG(hospital_los_days) AS mean_los,
  APPROX_QUANTILES(hospital_los_days, 1000)[OFFSET(500)] AS median_los,
  (COUNTIF(hospital_los_days <= 10) * 100.0) / COUNT(*) AS percent_le_10
FROM filtered
WHERE outcome IS NOT NULL
GROUP BY outcome;