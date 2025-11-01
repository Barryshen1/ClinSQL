WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 84 AND 94
),
all_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN qualifying_patients qp ON a.subject_id = qp.subject_id
  WHERE hadm_id IS NOT NULL
),
echo_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%echocardiography%'
     OR LOWER(long_title) LIKE '%echocardiogram%'
),
proc_counts AS (
  SELECT pi.subject_id, pi.hadm_id, COUNT(DISTINCT CONCAT(pi.icd_code, pi.icd_version)) AS num_distinct_echo
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN qualifying_patients qp ON pi.subject_id = qp.subject_id
  INNER JOIN echo_codes ec ON pi.icd_code = ec.icd_code AND pi.icd_version = ec.icd_version
  GROUP BY pi.subject_id, pi.hadm_id
),
counts_with_zero AS (
  SELECT ah.hadm_id, COALESCE(pc.num_distinct_echo, 0) AS num_distinct_echo
  FROM all_hadms ah
  LEFT JOIN proc_counts pc ON ah.hadm_id = pc.hadm_id
)
SELECT PERCENTILE_CONT(num_distinct_echo, 0.25) OVER() AS p25_num_distinct_echo
FROM counts_with_zero
LIMIT 1;