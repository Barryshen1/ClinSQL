WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),
echo_procedures AS (
  SELECT 
    ep.subject_id,
    pi.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS distinct_echo_count
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ep.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON a.subject_id = pi.subject_id
    AND a.hadm_id = pi.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%echocardiography%'
     OR LOWER(dip.long_title) LIKE '%echo%'
  GROUP BY ep.subject_id, pi.hadm_id
)
SELECT MAX(distinct_echo_count) AS max_distinct_echo_procedures
FROM echo_procedures;