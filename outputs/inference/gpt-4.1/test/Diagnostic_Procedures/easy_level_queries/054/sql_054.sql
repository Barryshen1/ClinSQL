WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),
echo_procedures AS (
  SELECT p.subject_id, a.hadm_id, pr.icd_code
  FROM cohort p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code AND pr.icd_version = dpr.icd_version
  WHERE LOWER(dpr.long_title) LIKE '%echocardiogram%'
     OR LOWER(dpr.long_title) LIKE '%echocardiography%'
),
per_admission_counts AS (
  SELECT subject_id, hadm_id, COUNT(DISTINCT icd_code) AS num_echo_procs
  FROM echo_procedures
  GROUP BY subject_id, hadm_id
),
per_patient_max AS (
  SELECT subject_id, MAX(num_echo_procs) AS max_echo_procs_per_admission
  FROM per_admission_counts
  GROUP BY subject_id
)
SELECT MAX(max_echo_procs_per_admission) AS max_distinct_echo_procs_per_patient
FROM per_patient_max
;