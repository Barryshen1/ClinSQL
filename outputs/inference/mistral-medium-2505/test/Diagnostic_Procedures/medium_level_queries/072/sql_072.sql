WITH
-- Get female patients aged 52-62
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 52 AND 62
),

-- Get admissions with acute pancreatitis (ICD-10: K85.* or ICD-9: 577.0)
pancreatitis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    -- Calculate length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'K85.%')
      OR (d.icd_version = 9 AND d.icd_code = '577.0')
    )
),

-- Count procedures per admission
procedures_per_admission AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE
    p.hadm_id IN (SELECT hadm_id FROM pancreatitis_admissions)
  GROUP BY
    p.hadm_id
),

-- Combine all data
admission_procedures AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    pa.seq_num,
    CASE WHEN pa.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type,
    CASE
      WHEN pa.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN pa.los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS los_group,
    COALESCE(ppa.procedure_count, 0) AS procedure_count
  FROM
    pancreatitis_admissions pa
  LEFT JOIN
    procedures_per_admission ppa
  ON
    pa.hadm_id = ppa.hadm_id
  WHERE
    pa.los_days BETWEEN 1 AND 8
)

-- Final aggregation
SELECT
  diagnosis_type,
  los_group,
  COUNT(hadm_id) AS admission_count,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM
  admission_procedures
GROUP BY
  diagnosis_type,
  los_group
ORDER BY
  diagnosis_type,
  los_group;