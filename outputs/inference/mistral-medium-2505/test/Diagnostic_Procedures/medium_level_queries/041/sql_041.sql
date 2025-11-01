WITH
-- Get male patients aged 51-61
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),

-- Get admissions with acute pancreatitis diagnosis
pancreatitis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    di.long_title,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN male_patients mp ON a.subject_id = mp.subject_id
  WHERE di.long_title LIKE '%pancreatitis%'
    AND di.long_title LIKE '%acute%'
),

-- Count radiography/CT procedures per admission
imaging_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT p.icd_code) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE dp.long_title LIKE '%radiography%'
     OR dp.long_title LIKE '%CT%'
     OR dp.long_title LIKE '%computed tomography%'
  GROUP BY hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    pa.hadm_id,
    pa.subject_id,
    pa.los_days,
    CASE WHEN pa.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type,
    CASE
      WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Other'
    END AS los_category,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM pancreatitis_admissions pa
  LEFT JOIN imaging_counts ic ON pa.hadm_id = ic.hadm_id
  WHERE pa.los_days BETWEEN 1 AND 7
)

-- Final aggregation
SELECT
  los_category,
  diagnosis_type,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(imaging_count) AS mean_imaging_per_admission
FROM combined_data
GROUP BY los_category, diagnosis_type
ORDER BY los_category, diagnosis_type;