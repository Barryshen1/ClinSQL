WITH patient_admissions AS (
  -- Base cohort: men aged 64-74 with hospital admissions
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),
antiplatelet_prescriptions AS (
  -- All antiplatelet prescriptions for cohort
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    pa.dischtime,
    DATE_DIFF(
      DATE(COALESCE(pr.stoptime, pa.dischtime)), 
      DATE(pr.starttime), 
      DAY
    ) + 1 AS duration_days  -- Inclusive days to end of prescription or discharge
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pa.subject_id = pr.subject_id 
    AND pa.hadm_id = pr.hadm_id
  WHERE (LOWER(pr.drug) LIKE '%aspirin%' 
         OR LOWER(pr.drug) LIKE '%clopidogrel%' 
         OR LOWER(pr.drug) LIKE '%prasugrel%' 
         OR LOWER(pr.drug) LIKE '%ticagrelor%')
    AND pr.starttime IS NOT NULL
),
combo_therapy_adms AS (
  -- Admissions with both aspirin AND a P2Y12 inhibitor
  SELECT 
    subject_id,
    hadm_id
  FROM (
    SELECT DISTINCT
      subject_id,
      hadm_id,
      MAX(CASE WHEN LOWER(drug) LIKE '%aspirin%' THEN 1 ELSE 0 END) OVER (PARTITION BY subject_id, hadm_id) AS has_aspirin,
      MAX(CASE WHEN LOWER(drug) LIKE '%clopidogrel%' OR LOWER(drug) LIKE '%prasugrel%' OR LOWER(drug) LIKE '%ticagrelor%' THEN 1 ELSE 0 END) OVER (PARTITION BY subject_id, hadm_id) AS has_p2y12
    FROM antiplatelet_prescriptions
  )
  WHERE has_aspirin = 1 AND has_p2y12 = 1
),
admission_durations AS (
  -- Sum durations per qualifying admission (total antiplatelet exposure days)
  SELECT 
    ct.hadm_id,
    SUM(ap.duration_days) AS total_antiplatelet_days
  FROM combo_therapy_adms ct
  INNER JOIN antiplatelet_prescriptions ap
    ON ct.subject_id = ap.subject_id 
    AND ct.hadm_id = ap.hadm_id
  GROUP BY ct.hadm_id
  HAVING total_antiplatelet_days > 0  -- Exclude zero-duration admissions
)
-- Compute median across admissions
SELECT 
  APPROX_QUANTILES(total_antiplatelet_days, 2)[OFFSET(1)] AS median_duration_days
FROM admission_durations;