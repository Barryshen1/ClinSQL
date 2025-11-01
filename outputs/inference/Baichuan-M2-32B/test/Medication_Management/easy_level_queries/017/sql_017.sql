WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    (p.anchor_year - p.anchor_age) AS birth_year,
    FLOOR(DATE_DIFF(a.admittime, DATE((p.anchor_year - p.anchor_age), 1, 1), DAY) / 365.25) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
),
warfarin_prescriptions AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.age_at_admission,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON pa.subject_id = pr.subject_id AND pa.hadm_id = pr.hadm_id
  WHERE 
    (pr.drug LIKE '%warfarin%' OR pr.drug LIKE '%Coumadin%')
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
    AND pa.age_at_admission BETWEEN 43 AND 53
)
SELECT 
  AVG(duration_days) AS avg_duration_days
FROM warfarin_prescriptions;