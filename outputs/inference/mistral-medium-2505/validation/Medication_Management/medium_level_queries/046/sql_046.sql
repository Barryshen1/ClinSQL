WITH
-- Define age range and gender filter
patient_filter AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 63 AND 73
),

-- Get admissions with T2DM and HF diagnoses
admissions_with_diagnoses AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS admission_duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_filter p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  WHERE
    -- T2DM (ICD-10: E11.x)
    (d1.icd_code LIKE 'E11%' OR d1.icd_code LIKE '250.%')
    -- HF (ICD-10: I50.x or ICD-9: 428.x)
    AND (d2.icd_code LIKE 'I50%' OR d2.icd_code LIKE '428.%')
    AND d1.seq_num <> d2.seq_num  -- Ensure different diagnoses
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 24  -- At least 24h admission
),

-- Get insulin medications (using prescriptions table)
insulin_meds AS (
  SELECT DISTINCT
    subject_id,
    hadm_id,
    drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%insulin%'
),

-- Get oral diabetes medications
oral_agents AS (
  SELECT DISTINCT
    subject_id,
    hadm_id,
    drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) IN (
      'metformin', 'glipizide', 'glyburide', 'glimepiride',
      'pioglitazone', 'rosiglitazone', 'sitagliptin', 'saxagliptin',
      'linagliptin', 'alogliptin', 'canagliflozin', 'dapagliflozin',
      'empagliflozin', 'ertugliflozin', 'acarbose', 'miglitol',
      'repaglinide', 'nateglinide'
    )
),

-- Patients with insulin in first 24h
insulin_first_24h AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    admissions_with_diagnoses a
  JOIN
    insulin_meds i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
  WHERE
    p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
),

-- Patients with oral agents in first 24h
oral_first_24h AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    admissions_with_diagnoses a
  JOIN
    oral_agents o ON a.subject_id = o.subject_id AND a.hadm_id = o.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON o.subject_id = p.subject_id AND o.hadm_id = p.hadm_id
  WHERE
    p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
),

-- Patients with insulin in final 24h
insulin_final_24h AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    admissions_with_diagnoses a
  JOIN
    insulin_meds i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
  WHERE
    p.starttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 24 HOUR) AND a.dischtime
),

-- Patients with oral agents in final 24h
oral_final_24h AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    admissions_with_diagnoses a
  JOIN
    oral_agents o ON a.subject_id = o.subject_id AND a.hadm_id = o.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON o.subject_id = p.subject_id AND o.hadm_id = p.hadm_id
  WHERE
    p.starttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 24 HOUR) AND a.dischtime
),

-- Count patients in each category
counts AS (
  SELECT
    COUNT(DISTINCT a.subject_id) AS total_patients,
    COUNT(DISTINCT i1.subject_id) AS insulin_first_24h_count,
    COUNT(DISTINCT o1.subject_id) AS oral_first_24h_count,
    COUNT(DISTINCT i2.subject_id) AS insulin_final_24h_count,
    COUNT(DISTINCT o2.subject_id) AS oral_final_24h_count
  FROM
    admissions_with_diagnoses a
  LEFT JOIN
    insulin_first_24h i1 ON a.subject_id = i1.subject_id AND a.hadm_id = i1.hadm_id
  LEFT JOIN
    oral_first_24h o1 ON a.subject_id = o1.subject_id AND a.hadm_id = o1.hadm_id
  LEFT JOIN
    insulin_final_24h i2 ON a.subject_id = i2.subject_id AND a.hadm_id = i2.hadm_id
  LEFT JOIN
    oral_final_24h o2 ON a.subject_id = o2.subject_id AND a.hadm_id = o2.hadm_id
)

-- Final result with prevalence calculations
SELECT
  total_patients,
  ROUND(100 * insulin_first_24h_count / total_patients, 1) AS insulin_first_24h_prevalence,
  ROUND(100 * oral_first_24h_count / total_patients, 1) AS oral_first_24h_prevalence,
  ROUND(100 * insulin_final_24h_count / total_patients, 1) AS insulin_final_24h_prevalence,
  ROUND(100 * oral_final_24h_count / total_patients, 1) AS oral_final_24h_prevalence,
  ROUND(100 * (insulin_final_24h_count - insulin_first_24h_count) / total_patients, 1) AS insulin_net_change_pp,
  ROUND(100 * (oral_final_24h_count - oral_first_24h_count) / total_patients, 1) AS oral_net_change_pp
FROM
  counts;