WITH echocardiography_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%echocardiogram%' OR LOWER(long_title) LIKE '%echocardiography%'
),
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 81 AND 91
),
echo_procedures AS (
  SELECT 
    picd.subject_id,
    picd.hadm_id,
    COUNT(DISTINCT picd.seq_num) AS distinct_echo_count
  FROM filtered_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
    ON p.subject_id = picd.subject_id
  JOIN echocardiography_codes ec
    ON picd.icd_code = ec.icd_code AND picd.icd_version = ec.icd_version
  GROUP BY picd.subject_id, picd.hadm_id
),
max_per_patient AS (
  SELECT 
    subject_id,
    MAX(distinct_echo_count) AS max_echo_per_patient
  FROM echo_procedures
  GROUP BY subject_id
)
SELECT 
  MAX(max_echo_per_patient) AS max_distinct_echo_procedures_per_patient
FROM max_per_patient;