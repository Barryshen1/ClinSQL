WITH
-- Get male patients aged 45-55
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 45 AND 55
),

-- Get admissions with T2DM and heart failure
t2dm_hf_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_patients mp ON a.subject_id = mp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_t2dm ON a.hadm_id = diag_t2dm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_t2dm ON diag_t2dm.icd_code = d_t2dm.icd_code
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_hf ON a.hadm_id = diag_hf.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_hf ON diag_hf.icd_code = d_hf.icd_code
  WHERE d_t2dm.icd_code LIKE 'E11%'  -- T2DM codes
    AND d_hf.icd_code LIKE 'I50%'     -- Heart failure codes
),

-- Get GLP-1 prescriptions
glp1_prescriptions AS (
  SELECT DISTINCT subject_id, hadm_id, starttime, stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%glp-1%'
     OR LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%lixisenatide%'
),

-- Patients started on GLP-1 within 72h of admission
started_within_72h AS (
  SELECT DISTINCT t.subject_id
  FROM t2dm_hf_admissions t
  JOIN glp1_prescriptions g ON t.subject_id = g.subject_id AND t.hadm_id = g.hadm_id
  WHERE TIMESTAMP_DIFF(g.starttime, CAST(t.admittime AS TIMESTAMP), HOUR) <= 72
),

-- Patients on GLP-1 in last 48h of admission
on_in_last_48h AS (
  SELECT DISTINCT t.subject_id
  FROM t2dm_hf_admissions t
  JOIN glp1_prescriptions g ON t.subject_id = g.subject_id AND t.hadm_id = g.hadm_id
  WHERE (g.stoptime IS NOT NULL AND TIMESTAMP_DIFF(CAST(t.dischtime AS TIMESTAMP), g.stoptime, HOUR) <= 48)
     OR (g.stoptime IS NULL AND TIMESTAMP_DIFF(CAST(t.dischtime AS TIMESTAMP), g.starttime, HOUR) <= 48)
),

-- Counts for calculations
counts AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN subject_id IN (SELECT subject_id FROM started_within_72h) THEN subject_id END) AS started_72h_count,
    COUNT(DISTINCT CASE WHEN subject_id IN (SELECT subject_id FROM on_in_last_48h) THEN subject_id END) AS on_48h_count
  FROM t2dm_hf_admissions
)

-- Final results
SELECT
  total_patients,
  started_72h_count,
  on_48h_count,
  ROUND(100 * started_72h_count / total_patients, 2) AS percent_started_within_72h,
  ROUND(100 * on_48h_count / total_patients, 2) AS percent_on_in_last_48h,
  ROUND(100 * (started_72h_count - on_48h_count) / total_patients, 2) AS net_change_percentage
FROM counts;