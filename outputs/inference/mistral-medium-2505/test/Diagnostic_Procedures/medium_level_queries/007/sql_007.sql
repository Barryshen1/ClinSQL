WITH
-- Get female patients aged 50-60
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 50 AND 60
),

-- Get admissions for these patients with ACS diagnosis
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    -- ACS ICD-10 codes (I20-I25)
    (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'
     OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE 'I24%' OR d.icd_code LIKE 'I25%')
    AND d.icd_version = 10
),

-- Count procedures per admission
procedure_counts AS (
  SELECT
    aa.hadm_id,
    aa.los_days,
    aa.seq_num AS diagnosis_seq_num,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM
    acs_admissions aa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON aa.hadm_id = p.hadm_id
  GROUP BY
    aa.hadm_id, aa.los_days, aa.seq_num
),

-- Categorize by LOS and diagnosis type
categorized_procedures AS (
  SELECT
    hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE 'Other'
    END AS los_category,
    CASE
      WHEN diagnosis_seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type,
    procedure_count
  FROM
    procedure_counts
  WHERE
    los_days BETWEEN 1 AND 8
)

-- Calculate percentiles
SELECT
  los_category,
  diagnosis_type,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(3)] AS p75
FROM
  categorized_procedures
GROUP BY
  los_category, diagnosis_type
ORDER BY
  los_category, diagnosis_type;