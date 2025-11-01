WITH
-- Get AKI admissions with age, gender, and LOS
aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    d.seq_num,
    d.icd_code,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admission_year,
    CASE WHEN d.seq_num = 1 THEN 'Primary AKI' ELSE 'Secondary AKI' END AS aki_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    -- AKI ICD-10 codes (N17.x)
    d.icd_code LIKE 'N17%'
    -- Age between 43-53 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    -- Male patients
    AND p.gender = 'M'
    -- LOS between 1-7 days
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Count MRI/CT procedures per admission
imaging_counts AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON h.hcpcs_cd = dh.code
  WHERE
    -- Filter for MRI/CT procedures (example codes - adjust as needed)
    (h.hcpcs_cd LIKE '704%' OR h.hcpcs_cd LIKE '705%')
    AND dh.category IN (1, 2)  -- Changed from string to numeric values
  GROUP BY
    h.subject_id, h.hadm_id
),

-- Combine AKI admissions with imaging counts
combined_data AS (
  SELECT
    aa.hadm_id,
    aa.los_days,
    aa.aki_type,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM
    aki_admissions aa
  LEFT JOIN
    imaging_counts ic ON aa.hadm_id = ic.hadm_id
)

-- Final aggregation
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_group,
  aki_type,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(imaging_count) AS mean_imaging_per_admission
FROM
  combined_data
GROUP BY
  los_group, aki_type
ORDER BY
  los_group, aki_type;