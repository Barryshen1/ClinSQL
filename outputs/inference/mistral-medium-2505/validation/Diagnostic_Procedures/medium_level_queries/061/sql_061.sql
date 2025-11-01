WITH
-- Get female patients aged 64-74
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
),

-- Get admissions with AKI diagnosis
aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.seq_num,
    CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS aki_diagnosis_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS admission_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
  WHERE a.subject_id IN (SELECT subject_id FROM female_patients)
    AND a.dischtime IS NOT NULL
    AND (LOWER(dicd.long_title) LIKE '%acute kidney injury%'
         OR LOWER(dicd.long_title) LIKE '%acute renal failure%')
),

-- Get imaging studies per admission (using HCPCS codes for imaging)
imaging_studies AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.long_description) LIKE '%imaging%'
     OR LOWER(dh.long_description) LIKE '%radiology%'
     OR LOWER(dh.long_description) LIKE '%ct%'
     OR LOWER(dh.long_description) LIKE '%mri%'
     OR LOWER(dh.long_description) LIKE '%x-ray%'
     OR LOWER(dh.long_description) LIKE '%ultrasound%'
  GROUP BY h.subject_id, h.hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    aa.hadm_id,
    aa.aki_diagnosis_type,
    CASE
      WHEN aa.admission_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN aa.admission_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS admission_duration,
    COALESCE(is.imaging_count, 0) AS imaging_count
  FROM aki_admissions aa
  LEFT JOIN imaging_studies is
    ON aa.subject_id = is.subject_id AND aa.hadm_id = is.hadm_id
  WHERE aa.admission_days BETWEEN 1 AND 7
    AND admission_duration IS NOT NULL
)

-- Final aggregation
SELECT
  aki_diagnosis_type,
  admission_duration,
  COUNT(hadm_id) AS admission_count,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(50)] AS median_imaging_count,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(25)] AS q1_imaging_count,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(75)] AS q3_imaging_count
FROM combined_data
GROUP BY aki_diagnosis_type, admission_duration
ORDER BY aki_diagnosis_type, admission_duration;