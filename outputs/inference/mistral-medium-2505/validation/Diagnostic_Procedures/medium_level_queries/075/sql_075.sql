WITH
-- Get male patients aged 59-69
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 59 AND 69
),

-- Get ACS admissions (ICD-9: 410.xx, ICD-10: I21.x)
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.seq_num,
    CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS admission_length_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_patients)
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410.%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
    )
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),

-- Count diagnostic procedures per admission
procedure_counts AS (
  SELECT
    aa.hadm_id,
    aa.diagnosis_type,
    CASE
      WHEN aa.admission_length_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN aa.admission_length_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS length_category,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM
    acs_admissions aa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON aa.hadm_id = p.hadm_id
  WHERE
    p.icd_code IS NOT NULL
  GROUP BY
    aa.hadm_id, aa.diagnosis_type, length_category
)

-- Calculate percentiles
SELECT
  diagnosis_type,
  length_category,
  COUNT(DISTINCT hadm_id) AS admission_count,
  PERCENTILE_CONT(procedure_count, 0.25) OVER(PARTITION BY diagnosis_type, length_category) AS p25_procedures,
  PERCENTILE_CONT(procedure_count, 0.5) OVER(PARTITION BY diagnosis_type, length_category) AS p50_procedures,
  PERCENTILE_CONT(procedure_count, 0.75) OVER(PARTITION BY diagnosis_type, length_category) AS p75_procedures
FROM
  procedure_counts
WHERE
  length_category IS NOT NULL
GROUP BY
  diagnosis_type, length_category, hadm_id, procedure_count
ORDER BY
  diagnosis_type, length_category;