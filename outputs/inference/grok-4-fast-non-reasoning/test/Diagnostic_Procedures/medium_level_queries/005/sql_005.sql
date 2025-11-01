WITH stroke_admissions AS (
  -- Identify admissions with ischemic stroke (primary or secondary)
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    -- LOS in days
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los,
    -- Primary diagnosis flag
    CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END AS is_primary
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      -- ICD-9 ischemic stroke (occlusion of cerebral arteries)
      (di.icd_version = 9 AND di.icd_code LIKE '43[0-4]%')
      OR
      -- ICD-10 ischemic stroke
      (di.icd_version = 10 AND di.icd_code LIKE 'I63%')
    )
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 8  -- Only 1-8 day stays
),

diagnostic_procs AS (
  -- Count distinct diagnostic procedures per admission
  SELECT 
    pi.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS proc_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  WHERE 
    -- ICD-9 diagnostic procedures (surgical: imaging, etc.)
    ((pi.icd_version = 9 AND pi.icd_code LIKE '87%') OR pi.icd_code LIKE '88%')
    OR
    -- ICD-10 PCS diagnostic (B codes: imaging, nuclear med, etc.)
    (pi.icd_version = 10 AND pi.icd_code LIKE 'B[0-9][0-9]%')
  GROUP BY 
    pi.hadm_id
),

admissions_with_procs AS (
  -- Join admissions to procedure counts (0 if none)
  SELECT 
    sa.*,
    COALESCE(dp.proc_count, 0) AS num_procs
  FROM 
    stroke_admissions sa
  LEFT JOIN 
    diagnostic_procs dp
    ON sa.hadm_id = dp.hadm_id
)

-- Aggregate statistics by LOS bin and primary/secondary
SELECT 
  los_bin,
  diagnosis_type,
  ROUND(AVG(num_procs), 2) AS mean_procs,
  MIN(num_procs) AS min_procs,
  MAX(num_procs) AS max_procs,
  COUNT(*) AS num_admissions
FROM (
  SELECT 
    num_procs,
    CASE 
      WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
      ELSE '5-8 days'
    END AS los_bin,
    CASE 
      WHEN is_primary = 1 THEN 'Primary diagnosis'
      ELSE 'Secondary diagnosis'
    END AS diagnosis_type
  FROM 
    admissions_with_procs
)
GROUP BY 
  los_bin, diagnosis_type
ORDER BY 
  los_bin, diagnosis_type;