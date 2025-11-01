WITH ace_inhibitors AS (
  SELECT 'lisinopril' AS drug_name
  UNION ALL SELECT 'enalapril'
  UNION ALL SELECT 'ramipril'
  UNION ALL SELECT 'captopril'
  UNION ALL SELECT 'benazepril'
  UNION ALL SELECT 'fosinopril'
  UNION ALL SELECT 'moexipril'
  UNION ALL SELECT 'perindopril'
  UNION ALL SELECT 'quinapril'
  UNION ALL SELECT 'trandolapril'
),
patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    DATETIME(p.anchor_year, 1, 1, 0, 0, 0) AS anchor_datetime,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
),
prescription_durations AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON pa.hadm_id = pr.hadm_id
  INNER JOIN ace_inhibitors ai
    ON LOWER(TRIM(pr.drug)) = ai.drug_name
  WHERE
    pa.gender = 'F'
    AND pa.age_at_admit BETWEEN 78 AND 88
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
)
SELECT
  ROUND(STDDEV(duration_days), 2) AS ace_inhibitor_duration_sd_days
FROM prescription_durations;