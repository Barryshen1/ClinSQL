WITH echo_procs AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.icd_code,
    pr.icd_version,
    dp.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(dp.long_title) LIKE '%echocardi%'
)
, counts_per_hosp AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS distinct_echo_proc_count
  FROM echo_procs
  GROUP BY subject_id, hadm_id
)
SELECT
  MAX(distinct_echo_proc_count) AS max_distinct_echo_procs_per_patient
FROM counts_per_hosp;