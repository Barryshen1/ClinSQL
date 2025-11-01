WITH
-- Define LGIB ICD codes (example codes, adjust as needed)
lgib_icd_codes AS (
  SELECT 'K92.2' AS icd_code UNION ALL
  SELECT 'K55.21' UNION ALL
  SELECT 'K57.32' UNION ALL
  SELECT 'K62.5' UNION ALL
  SELECT 'K63.81'
),

-- Define radiography/CT procedure codes (example codes, adjust as needed)
radiography_ct_codes AS (
  SELECT '74230' AS code UNION ALL  -- Example CPT code for CT
  SELECT '74240' UNION ALL
  SELECT '74246' UNION ALL
  SELECT '74247' UNION ALL
  SELECT '74248' UNION ALL
  SELECT '74249' UNION ALL
  SELECT '74250' UNION ALL
  SELECT '74251' UNION ALL
  SELECT '74252' UNION ALL
  SELECT '74260' UNION ALL
  SELECT '74261' UNION ALL
  SELECT '74262' UNION ALL
  SELECT '74263' UNION ALL
  SELECT '74270' UNION ALL
  SELECT '74280' UNION ALL
  SELECT '74283' UNION ALL
  SELECT '74285' UNION ALL
  SELECT '74290' UNION ALL
  SELECT '74291' UNION ALL
  SELECT '74292' UNION ALL
  SELECT '74293' UNION ALL
  SELECT '74294' UNION ALL
  SELECT '74295' UNION ALL
  SELECT '74296' UNION ALL
  SELECT '74297' UNION ALL
  SELECT '74298' UNION ALL
  SELECT '74299'
),

-- Get female patients aged 71-81 with LGIB
lgib_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS admission_days,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    di.long_title AS diagnosis_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.icd_code IN (SELECT icd_code FROM lgib_icd_codes)
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Count radiography/CT procedures per admission
radiography_ct_counts AS (
  SELECT
    l.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS radiography_ct_count
  FROM
    lgib_patients l
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h ON l.hadm_id = h.hadm_id
  WHERE
    h.hcpcs_cd IN (SELECT code FROM radiography_ct_codes)
  GROUP BY
    l.hadm_id
)

-- Final aggregation
SELECT
  CASE
    WHEN l.admission_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN l.admission_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other duration'
  END AS admission_duration_category,
  CASE
    WHEN l.seq_num = 1 THEN 'Primary diagnosis'
    ELSE 'Secondary diagnosis'
  END AS diagnosis_type,
  AVG(COALESCE(r.radiography_ct_count, 0)) AS mean_radiography_ct_count,
  COUNT(DISTINCT l.hadm_id) AS admission_count
FROM
  lgib_patients l
LEFT JOIN
  radiography_ct_counts r ON l.hadm_id = r.hadm_id
WHERE
  l.admission_days BETWEEN 1 AND 7
GROUP BY
  admission_duration_category,
  diagnosis_type
ORDER BY
  admission_duration_category,
  diagnosis_type;