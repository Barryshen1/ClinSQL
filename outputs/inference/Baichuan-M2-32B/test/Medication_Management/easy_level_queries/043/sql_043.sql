WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),
admissions_with_duration AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
),
prescription_flags AS (
  SELECT DISTINCT
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE p.drug IS NOT NULL
    AND (LOWER(p.drug) LIKE '%hydralazine%'
         OR LOWER(p.drug) LIKE '%isosorbide dinitrate%')
)
SELECT MIN(los_days) AS shortest_los
FROM admissions_with_duration ad
JOIN prescription_flags pf ON ad.hadm_id = pf.hadm_id;