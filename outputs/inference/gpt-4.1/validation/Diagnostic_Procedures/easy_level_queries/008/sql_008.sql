WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),
echo_procedure_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%echocardiogram%'
     OR LOWER(long_title) LIKE '%echocardiography%'
),
echo_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pi.icd_code) AS num_echo_procedures
  FROM female_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON p.subject_id = pi.subject_id
  LEFT JOIN echo_procedure_codes epc
    ON pi.icd_code = epc.icd_code
    AND pi.icd_version = epc.icd_version
  GROUP BY p.subject_id
)
SELECT
  PERCENTILE_CONT(num_echo_procedures, 0.25) OVER() AS echo_procedure_25th_percentile
FROM echo_counts;