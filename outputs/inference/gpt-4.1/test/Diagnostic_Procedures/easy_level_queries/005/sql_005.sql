WITH male_patients_57_67 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),
echo_procedures AS (
  SELECT p.subject_id, proc.icd_code
  FROM male_patients_57_67 p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%echocardiogram%'
     OR LOWER(dproc.long_title) LIKE '%echocardiography%'
),
echo_counts_per_patient AS (
  SELECT subject_id, COUNT(DISTINCT icd_code) AS num_echo_procs
  FROM echo_procedures
  GROUP BY subject_id
)
SELECT
  APPROX_QUANTILES(num_echo_procs, 4)[OFFSET(3)] AS echo_procs_75th_percentile
FROM echo_counts_per_patient;