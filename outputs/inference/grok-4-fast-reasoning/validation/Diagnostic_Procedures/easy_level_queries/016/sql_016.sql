WITH relevant_procs AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%electrocardiogram%'
     OR LOWER(long_title) LIKE '%ecg%'
     OR LOWER(long_title) LIKE '%telemetry%'
     OR LOWER(long_title) LIKE '%cardiac monitoring%'
     OR LOWER(long_title) LIKE '%holter%'
     OR LOWER(long_title) LIKE '%ambulatory ecg%'
),
filtered_procs AS (
  SELECT pi.hadm_id, pi.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN relevant_procs rp
    ON pi.icd_code = rp.icd_code 
    AND pi.icd_version = rp.icd_version
),
eligible_admissions AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.hadm_id IS NOT NULL
),
proc_counts AS (
  SELECT 
    ea.hadm_id,
    COUNT(DISTINCT fp.icd_code) AS num_distinct_procs
  FROM eligible_admissions ea
  LEFT JOIN filtered_procs fp
    ON ea.hadm_id = fp.hadm_id
  GROUP BY ea.hadm_id
)
SELECT 
  APPROX_QUANTILES(num_distinct_procs, 4)[OFFSET(3)] AS p75th_percentile
FROM proc_counts;