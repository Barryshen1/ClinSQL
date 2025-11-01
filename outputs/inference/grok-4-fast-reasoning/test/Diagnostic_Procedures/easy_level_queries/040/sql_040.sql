WITH relevant_procs AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%ecg%'
     OR LOWER(long_title) LIKE '%electrocardiogram%'
     OR LOWER(long_title) LIKE '%ekg%'
     OR LOWER(long_title) LIKE '%telemetry%'
     OR LOWER(long_title) LIKE '%rhythm strip%'
     OR LOWER(long_title) LIKE '%cardiac monitoring%'
),
patient_counts AS (
  SELECT 
    p.subject_id, 
    COUNT(DISTINCT rp.icd_code) AS num_distinct
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
    ON p.subject_id = pi.subject_id
  LEFT JOIN relevant_procs rp 
    ON pi.icd_code = rp.icd_code 
    AND pi.icd_version = rp.icd_version
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 51 AND 61
  GROUP BY p.subject_id
)
SELECT APPROX_QUANTILES(num_distinct, 4)[OFFSET(1)] AS p25th_percentile
FROM patient_counts;