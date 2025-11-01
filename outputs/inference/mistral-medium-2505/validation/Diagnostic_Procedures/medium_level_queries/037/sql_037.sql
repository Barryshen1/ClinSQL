WITH
-- Get male patients aged 43-53
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 43 AND 53
),

-- Get AMI admissions (primary and secondary)
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS ami_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN male_patients p ON a.subject_id = p.subject_id
  WHERE d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Count radiography/CT procedures per admission
radiology_counts AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS radiology_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN ami_admissions a
    ON h.subject_id = a.subject_id AND h.hadm_id = a.hadm_id
  WHERE h.hcpcs_cd LIKE '7%' OR h.hcpcs_cd LIKE '76%'
  GROUP BY h.subject_id, h.hadm_id
),

-- Combine all data
final_data AS (
  SELECT
    a.ami_type,
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS stay_duration,
    COALESCE(r.radiology_count, 0) AS radiology_count
  FROM ami_admissions a
  LEFT JOIN radiology_counts r
    ON a.subject_id = r.subject_id AND a.hadm_id = r.hadm_id
)

-- Calculate median and IQR
SELECT
  ami_type,
  stay_duration,
  COUNT(*) AS admission_count,
  APPROX_QUANTILES(radiology_count, 4)[OFFSET(1)] AS median_radiology,
  APPROX_QUANTILES(radiology_count, 4)[OFFSET(0)] AS q1_radiology,
  APPROX_QUANTILES(radiology_count, 4)[OFFSET(2)] AS q3_radiology
FROM final_data
GROUP BY ami_type, stay_duration
ORDER BY ami_type, stay_duration;