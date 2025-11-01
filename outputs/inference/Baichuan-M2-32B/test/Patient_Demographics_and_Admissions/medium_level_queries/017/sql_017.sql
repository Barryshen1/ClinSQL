WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute birth date using anchor_year and anchor_age
    DATE(p.anchor_year - p.anchor_age, 1, 1) AS birth_date,
    -- Compute age at admission
    TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 38 AND 48
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.subject_id = a.subject_id
        AND i.hadm_id = a.hadm_id
    )
)
SELECT
  discharge_category,
  COUNT(*) AS num_hospitalizations,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(90)] AS p90_los
FROM (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location LIKE '%HOME%' THEN 'home'
      ELSE 'facility'
    END AS discharge_category
  FROM patient_admissions
)
GROUP BY discharge_category
ORDER BY discharge_category;