WITH qualifying_subjects AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age >= 52
    AND anchor_age <= 62
),
qualifying_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN qualifying_subjects qs ON a.subject_id = qs.subject_id
  WHERE hadm_id IS NOT NULL
),
valve_procedure_codes AS (
  SELECT DISTINCT p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  INNER JOIN qualifying_admissions qa ON p.hadm_id = qa.hadm_id
  WHERE LOWER(d.long_title) LIKE '%valve%'
    AND (LOWER(d.long_title) LIKE '%repair%' 
         OR LOWER(d.long_title) LIKE '%replacement%' 
         OR LOWER(d.long_title) LIKE '%valvuloplasty%')
),
counts_per_hadm AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_distinct_valve_procs
  FROM valve_procedure_codes
  GROUP BY hadm_id
),
all_hadm_counts AS (
  SELECT hadm_id, num_distinct_valve_procs
  FROM counts_per_hadm
  UNION ALL
  SELECT hadm_id, 0 AS num_distinct_valve_procs
  FROM qualifying_admissions
  WHERE hadm_id NOT IN (SELECT hadm_id FROM counts_per_hadm)
)
SELECT
  APPROX_QUANTILES(num_distinct_valve_procs, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(num_distinct_valve_procs, 4)[OFFSET(3)] AS Q3,
  APPROX_QUANTILES(num_distinct_valve_procs, 4)[OFFSET(3)] - APPROX_QUANTILES(num_distinct_valve_procs, 4)[OFFSET(1)] AS IQR
FROM all_hadm_counts;