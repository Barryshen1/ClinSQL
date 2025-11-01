WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),
atorvastatin_prescriptions AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.age_at_admission,
    pr.starttime,
    pr.stoptime,
    pr.prod_strength,
    SAFE_CAST(REGEXP_EXTRACT(LOWER(pr.prod_strength), r'(\d+)') AS INT64) AS strength_num,
    TIMESTAMP_DIFF(COALESCE(pr.stoptime, pa.dischtime), pr.starttime, SECOND) / 86400.0 AS duration_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pa.hadm_id = pr.hadm_id
  WHERE pa.gender = 'F'
    AND pa.age_at_admission >= 60
    AND pa.age_at_admission <= 70
    AND LOWER(pr.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(REGEXP_EXTRACT(LOWER(pr.prod_strength), r'(\d+)') AS INT64) IN (40, 80)
    AND pr.starttime <= COALESCE(pr.stoptime, pa.dischtime)
)
SELECT 
  (PERCENTILE_CONT(duration_days, 0.75) OVER () - 
   PERCENTILE_CONT(duration_days, 0.25) OVER ()) AS iqr
FROM atorvastatin_prescriptions
LIMIT 1;