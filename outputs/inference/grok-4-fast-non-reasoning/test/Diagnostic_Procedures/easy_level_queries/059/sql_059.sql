WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' 
    AND anchor_age BETWEEN 76 AND 86
),
cardiac_procedures_per_hadm AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_cardiac_procs
  FROM filtered_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
    ON proc.icd_code = d_proc.icd_code 
    AND proc.icd_version = d_proc.icd_version
  WHERE LOWER(d_proc.long_title) LIKE '%heart%' 
     OR LOWER(d_proc.long_title) LIKE '%cardiac%'
  GROUP BY p.subject_id, a.hadm_id
)
SELECT 
  (SELECT APPROX_QUANTILES(distinct_cardiac_procs, 4)[OFFSET(0)] FROM cardiac_procedures_per_hadm) AS q1,
  (SELECT APPROX_QUANTILES(distinct_cardiac_procs, 4)[OFFSET(3)] FROM cardiac_procedures_per_hadm) AS q3,
  (SELECT APPROX_QUANTILES(distinct_cardiac_procs, 4)[OFFSET(3)] - APPROX_QUANTILES(distinct_cardiac_procs, 4)[OFFSET(0)] FROM cardiac_procedures_per_hadm) AS iqr;