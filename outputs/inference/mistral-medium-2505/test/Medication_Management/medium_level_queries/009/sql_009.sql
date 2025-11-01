WITH
-- Define age range and gender
eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- Identify patients with diabetes and acute HF
diabetes_hf_patients AS (
  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id,
    ep.admittime,
    ep.dischtime
  FROM
    eligible_patients ep
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_diabetes
  ON
    ep.hadm_id = diag_diabetes.hadm_id
    AND diag_diabetes.icd_code LIKE 'E11.%'  -- Type 2 diabetes
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_hf
  ON
    ep.hadm_id = diag_hf.hadm_id
    AND diag_hf.icd_code IN (
      'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9'  -- Acute heart failure codes
    )
),

-- Identify insulin prescriptions
insulin_prescriptions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    d.admittime,
    d.dischtime,
    p.starttime AS insulin_starttime
  FROM
    diabetes_hf_patients d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON
    d.hadm_id = p.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%insulin%'
),

-- Identify oral diabetes agent prescriptions
oral_agents_prescriptions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    d.admittime,
    d.dischtime,
    p.starttime AS oral_agent_starttime
  FROM
    diabetes_hf_patients d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON
    d.hadm_id = p.hadm_id
  WHERE
    LOWER(p.drug) IN (
      'metformin', 'glipizide', 'glyburide', 'glimepiride',
      'pioglitazone', 'rosiglitazone', 'sitagliptin', 'saxagliptin',
      'repaglinide', 'nateglinide', 'acarbose', 'miglitol',
      'canagliflozin', 'dapagliflozin', 'empagliflozin', 'ertugliflozin'
    )
),

-- Calculate first 24h and final 24h windows
time_windows AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR) AS first_24h_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AS final_24h_start
  FROM
    diabetes_hf_patients
),

-- Count insulin initiations in each time window
insulin_counts AS (
  SELECT
    COUNT(DISTINCT CASE WHEN i.insulin_starttime BETWEEN t.admittime AND t.first_24h_end THEN i.subject_id END) AS first_24h_insulin,
    COUNT(DISTINCT CASE WHEN i.insulin_starttime BETWEEN t.final_24h_start AND t.dischtime THEN i.subject_id END) AS final_24h_insulin,
    COUNT(DISTINCT t.subject_id) AS total_patients
  FROM
    time_windows t
  LEFT JOIN
    insulin_prescriptions i
  ON
    t.subject_id = i.subject_id AND t.hadm_id = i.hadm_id
),

-- Count oral agent initiations in each time window
oral_agents_counts AS (
  SELECT
    COUNT(DISTINCT CASE WHEN o.oral_agent_starttime BETWEEN t.admittime AND t.first_24h_end THEN o.subject_id END) AS first_24h_oral,
    COUNT(DISTINCT CASE WHEN o.oral_agent_starttime BETWEEN t.final_24h_start AND t.dischtime THEN o.subject_id END) AS final_24h_oral,
    COUNT(DISTINCT t.subject_id) AS total_patients
  FROM
    time_windows t
  LEFT JOIN
    oral_agents_prescriptions o
  ON
    t.subject_id = o.subject_id AND t.hadm_id = o.hadm_id
)

-- Final results
SELECT
  'Insulin' AS medication_type,
  ROUND(100 * first_24h_insulin / NULLIF(total_patients, 0), 2) AS first_24h_percentage,
  ROUND(100 * final_24h_insulin / NULLIF(total_patients, 0), 2) AS final_24h_percentage,
  ROUND(100 * (final_24h_insulin - first_24h_insulin) / NULLIF(total_patients, 0), 2) AS absolute_difference
FROM
  insulin_counts
WHERE
  total_patients > 0

UNION ALL

SELECT
  'Oral Agents' AS medication_type,
  ROUND(100 * first_24h_oral / NULLIF(total_patients, 0), 2) AS first_24h_percentage,
  ROUND(100 * final_24h_oral / NULLIF(total_patients, 0), 2) AS final_24h_percentage,
  ROUND(100 * (final_24h_oral - first_24h_oral) / NULLIF(total_patients, 0), 2) AS absolute_difference
FROM
  oral_agents_counts
WHERE
  total_patients > 0
ORDER BY
  medication_type;