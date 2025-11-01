WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 84 AND 94
),
echo_procedures AS (
  SELECT p.subject_id, p.hadm_id, pr.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` pr
    ON p.icd_code = pr.icd_code AND p.icd_version = pr.icd_version
  WHERE LOWER(pr.long_title) LIKE '%echocardiogram%'
     OR LOWER(pr.long_title) LIKE '%echocardiography%'
),
echo_per_admission AS (
  SELECT
    ep.subject_id,
    ep.hadm_id,
    COUNT(DISTINCT ep.icd_code) AS num_distinct_echo
  FROM echo_procedures ep
  WHERE ep.subject_id IN (SELECT subject_id FROM male_patients)
  GROUP BY ep.subject_id, ep.hadm_id
),
max_echo_per_patient AS (
  SELECT
    subject_id,
    MAX(num_distinct_echo) AS max_distinct_echo_per_admission
  FROM echo_per_admission
  GROUP BY subject_id
)
SELECT
  MAX(max_distinct_echo_per_admission) AS max_distinct_echo_per_patient
FROM max_echo_per_patient
;