WITH cohort AS (
  -- Base cohort: females aged 50-60 with ACS context
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hospital_expire_flag = 0  -- Exclude deaths
),

acs_admissions AS (
  -- Admissions with ACS (I20/I21 for ICD-10; 410/411.1 for ICD-9)
  SELECT 
    c.*,
    di.icd_code,
    di.icd_version,
    di.seq_num,
    dd.long_title
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON c.hadm_id = di.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE 
    (di.icd_version = 'ICD-10' AND (di.icd_code LIKE 'I20%' OR di.icd_code LIKE 'I21%'))
    OR (di.icd_version = 'ICD-9' AND (di.icd_code LIKE '410%' OR di.icd_code = '411.1'))
),

acs_classified AS (
  -- Classify admissions by primary (seq_num=1 for ACS) vs secondary ACS
  SELECT DISTINCT
    hadm_id,
    admittime,
    dischtime,
    anchor_age,
    CASE 
      WHEN MIN(CASE WHEN (icd_version = 'ICD-10' AND (icd_code LIKE 'I20%' OR icd_code LIKE 'I21%'))
                    OR (icd_version = 'ICD-9' AND (icd_code LIKE '410%' OR icd_code = '411.1'))
                    THEN seq_num END) OVER (PARTITION BY hadm_id) = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS acs_type
  FROM 
    acs_admissions
),

los_strat AS (
  -- Add LOS bucket
  SELECT 
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS los_bucket
  FROM 
    acs_classified
  WHERE 
    DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 8
),

procedure_counts AS (
  -- Count distinct diagnostic procedures per admission
  SELECT 
    ls.hadm_id,
    ls.los_bucket,
    ls.acs_type,
    COUNT(DISTINCT pi.icd_code) AS num_diagnostic_procs
  FROM 
    los_strat ls
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  ON ls.hadm_id = pi.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
  WHERE 
    LOWER(dp.long_title) LIKE '%diagnostic%'
    OR LOWER(dp.long_title) LIKE '%angiography%'
    OR LOWER(dp.long_title) LIKE '%catheterization%'
    OR LOWER(dp.long_title) LIKE '%echocardiogram%'
    OR LOWER(dp.long_title) LIKE '%cardiac%'
  GROUP BY 
    ls.hadm_id, ls.los_bucket, ls.acs_type
)

-- Final percentiles
SELECT 
  los_bucket,
  acs_type,
  PERCENTILE_CONT(num_diagnostic_procs, 0.25) AS p25_procs,
  PERCENTILE_CONT(num_diagnostic_procs, 0.50) AS p50_procs,
  PERCENTILE_CONT(num_diagnostic_procs, 0.75) AS p75_procs
FROM 
  procedure_counts
GROUP BY 
  los_bucket, acs_type
ORDER BY 
  los_bucket, acs_type;