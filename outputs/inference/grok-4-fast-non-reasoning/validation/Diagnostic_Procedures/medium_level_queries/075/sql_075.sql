WITH filtered_patients AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),

base_admissions AS (
  SELECT 
    fp.*,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM filtered_patients fp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fp.subject_id = a.subject_id
  WHERE a.hospital_expire_flag = 0
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

los_stratified AS (
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_stratum
  FROM base_admissions
),

-- Primary diagnosis procedures: procedures matching primary diag ICD code
primary_diag_procs AS (
  SELECT 
    ls.hadm_id,
    ls.los_stratum,
    COUNT(DISTINCT pi.icd_code) AS num_primary_procs
  FROM los_stratified ls
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ls.hadm_id = di.hadm_id
    AND di.seq_num = 1
    AND di.icd_version = 9
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON ls.hadm_id = pi.hadm_id
    AND pi.icd_code LIKE di.icd_code  -- Match procedure to primary diag code (approximate relevance)
    AND pi.icd_code LIKE '8%'
    AND pi.icd_version = 9
  GROUP BY ls.hadm_id, ls.los_stratum
),

-- Secondary diagnosis procedures: procedures matching any secondary diag ICD code
secondary_diag_procs AS (
  SELECT 
    ls.hadm_id,
    ls.los_stratum,
    COUNT(DISTINCT pi.icd_code) AS num_secondary_procs
  FROM los_stratified ls
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ls.hadm_id = di.hadm_id
    AND di.seq_num > 1
    AND di.icd_version = 9
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON ls.hadm_id = pi.hadm_id
    AND pi.icd_code LIKE di.icd_code  -- Match to secondary diag code
    AND pi.icd_code LIKE '8%'
    AND pi.icd_version = 9
  GROUP BY ls.hadm_id, ls.los_stratum
)

-- Combine and compute percentiles
SELECT 
  'Primary Diagnosis' AS diagnosis_type,
  los_stratum,
  PERCENTILE_CONT(num_primary_procs, 0.25) OVER (PARTITION BY los_stratum) AS p25,
  PERCENTILE_CONT(num_primary_procs, 0.50) OVER (PARTITION BY los_stratum) AS p50,
  PERCENTILE_CONT(num_primary_procs, 0.75) OVER (PARTITION BY los_stratum) AS p75
FROM primary_diag_procs

UNION ALL

SELECT 
  'Secondary Diagnosis' AS diagnosis_type,
  los_stratum,
  PERCENTILE_CONT(num_secondary_procs, 0.25) OVER (PARTITION BY los_stratum) AS p25,
  PERCENTILE_CONT(num_secondary_procs, 0.50) OVER (PARTITION BY los_stratum) AS p50,
  PERCENTILE_CONT(num_secondary_procs, 0.75) OVER (PARTITION BY los_stratum) AS p75
FROM secondary_diag_procs

ORDER BY diagnosis_type, los_stratum;