WITH
-- Get female patients aged 44-54 at admission
female_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),

-- Get patients with T2DM and heart failure
diabetes_hf_patients AS (
  SELECT
    fp.subject_id,
    fp.hadm_id,
    fp.admittime,
    fp.dischtime
  FROM
    female_patients fp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON
    fp.subject_id = diag.subject_id AND fp.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    -- T2DM ICD codes (ICD-9: 250.x0, 250.x2; ICD-10: E11.x)
    (diag.icd_code LIKE '250.%' AND (diag.icd_code LIKE '%.0' OR diag.icd_code LIKE '%.2'))
    OR (diag.icd_code LIKE 'E11.%')
    -- Heart failure ICD codes (ICD-9: 428.x; ICD-10: I50.x)
    OR (diag.icd_code LIKE '428.%')
    OR (diag.icd_code LIKE 'I50.%')
  GROUP BY
    fp.subject_id, fp.hadm_id, fp.admittime, fp.dischtime
  HAVING
    -- Must have both T2DM and heart failure
    COUNT(DISTINCT CASE WHEN (diag.icd_code LIKE '250.%' AND (diag.icd_code LIKE '%.0' OR diag.icd_code LIKE '%.2')) OR (diag.icd_code LIKE 'E11.%') THEN diag.icd_code END) > 0
    AND COUNT(DISTINCT CASE WHEN (diag.icd_code LIKE '428.%') OR (diag.icd_code LIKE 'I50.%') THEN diag.icd_code END) > 0
),

-- Get insulin and oral agent prescriptions
medications AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.admittime,
    d.dischtime,
    p.starttime,
    p.stoptime,
    p.drug,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' OR
           LOWER(p.drug) LIKE '%glipizide%' OR
           LOWER(p.drug) LIKE '%glyburide%' OR
           LOWER(p.drug) LIKE '%glimepiride%' OR
           LOWER(p.drug) LIKE '%pioglitazone%' OR
           LOWER(p.drug) LIKE '%rosiglitazone%' OR
           LOWER(p.drug) LIKE '%sitagliptin%' OR
           LOWER(p.drug) LIKE '%saxagliptin%' OR
           LOWER(p.drug) LIKE '%linagliptin%' OR
           LOWER(p.drug) LIKE '%alogliptin%' THEN 'Oral Agent'
      ELSE NULL
    END AS medication_type
  FROM
    diabetes_hf_patients d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON
    d.subject_id = p.subject_id AND d.hadm_id = p.hadm_id
  WHERE
    (LOWER(p.drug) LIKE '%insulin%' OR
     LOWER(p.drug) LIKE '%metformin%' OR
     LOWER(p.drug) LIKE '%glipizide%' OR
     LOWER(p.drug) LIKE '%glyburide%' OR
     LOWER(p.drug) LIKE '%glimepiride%' OR
     LOWER(p.drug) LIKE '%pioglitazone%' OR
     LOWER(p.drug) LIKE '%rosiglitazone%' OR
     LOWER(p.drug) LIKE '%sitagliptin%' OR
     LOWER(p.drug) LIKE '%saxagliptin%' OR
     LOWER(p.drug) LIKE '%linagliptin%' OR
     LOWER(p.drug) LIKE '%alogliptin%')
),

-- First 24h medications
first_24h_meds AS (
  SELECT
    subject_id,
    hadm_id,
    medication_type,
    COUNT(DISTINCT drug) AS drug_count
  FROM
    medications
  WHERE
    starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR)
  GROUP BY
    subject_id, hadm_id, medication_type
),

-- Last 48h medications
last_48h_meds AS (
  SELECT
    subject_id,
    hadm_id,
    medication_type,
    COUNT(DISTINCT drug) AS drug_count
  FROM
    medications
  WHERE
    starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime
  GROUP BY
    subject_id, hadm_id, medication_type
),

-- Combine medication data
combined_meds AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN f.medication_type = 'Insulin' THEN 1 ELSE 0 END) AS has_insulin_first,
    MAX(CASE WHEN f.medication_type = 'Oral Agent' THEN 1 ELSE 0 END) AS has_oral_first,
    MAX(CASE WHEN l.medication_type = 'Insulin' THEN 1 ELSE 0 END) AS has_insulin_last,
    MAX(CASE WHEN l.medication_type = 'Oral Agent' THEN 1 ELSE 0 END) AS has_oral_last
  FROM
    diabetes_hf_patients d
  LEFT JOIN
    first_24h_meds f
  ON
    d.subject_id = f.subject_id AND d.hadm_id = f.hadm_id
  LEFT JOIN
    last_48h_meds l
  ON
    d.subject_id = l.subject_id AND d.hadm_id = l.hadm_id
  GROUP BY
    d.subject_id, d.hadm_id
),

-- Calculate medication status
medication_status AS (
  SELECT
    subject_id,
    hadm_id,
    -- Insulin status
    CASE
      WHEN has_insulin_first = 1 AND has_insulin_last = 1 THEN 'Continued'
      WHEN has_insulin_first = 0 AND has_insulin_last = 1 THEN 'Initiated'
      WHEN has_insulin_first = 1 AND has_insulin_last = 0 THEN 'Discontinued'
      ELSE 'None'
    END AS insulin_status,
    -- Oral agent status
    CASE
      WHEN has_oral_first = 1 AND has_oral_last = 1 THEN 'Continued'
      WHEN has_oral_first = 0 AND has_oral_last = 1 THEN 'Initiated'
      WHEN has_oral_first = 1 AND has_oral_last = 0 THEN 'Discontinued'
      ELSE 'None'
    END AS oral_status
  FROM
    combined_meds
)

-- Final results
SELECT
  COUNT(DISTINCT subject_id) AS total_patients,
  -- Insulin statistics
  SUM(CASE WHEN insulin_status = 'Continued' THEN 1 ELSE 0 END) AS insulin_continued,
  SUM(CASE WHEN insulin_status = 'Initiated' THEN 1 ELSE 0 END) AS insulin_initiated,
  SUM(CASE WHEN insulin_status = 'Discontinued' THEN 1 ELSE 0 END) AS insulin_discontinued,
  SUM(CASE WHEN insulin_status = 'None' THEN 1 ELSE 0 END) AS insulin_none,
  -- Oral agent statistics
  SUM(CASE WHEN oral_status = 'Continued' THEN 1 ELSE 0 END) AS oral_continued,
  SUM(CASE WHEN oral_status = 'Initiated' THEN 1 ELSE 0 END) AS oral_initiated,
  SUM(CASE WHEN oral_status = 'Discontinued' THEN 1 ELSE 0 END) AS oral_discontinued,
  SUM(CASE WHEN oral_status = 'None' THEN 1 ELSE 0 END) AS oral_none,
  -- Percentages
  ROUND(SUM(CASE WHEN insulin_status = 'Continued' THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id), 1) AS insulin_continued_pct,
  ROUND(SUM(CASE WHEN insulin_status = 'Initiated' THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id), 1) AS insulin_initiated_pct,
  ROUND(SUM(CASE WHEN insulin_status = 'Discontinued' THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id), 1) AS insulin_discontinued_pct,
  ROUND(SUM(CASE WHEN oral_status = 'Continued' THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id), 1) AS oral_continued_pct,
  ROUND(SUM(CASE WHEN oral_status = 'Initiated' THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id), 1) AS oral_initiated_pct,
  ROUND(SUM(CASE WHEN oral_status = 'Discontinued' THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id), 1) AS oral_discontinued_pct
FROM
  medication_status;