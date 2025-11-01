WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age >= 64
    AND anchor_age <= 74
),
procedure_counts AS (
  SELECT p.subject_id, COUNT(DISTINCT p.hadm_id) AS num_procs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  INNER JOIN cohort c
    ON p.subject_id = c.subject_id
  WHERE LOWER(d.long_title) LIKE '%cardiac%'
    AND LOWER(d.long_title) LIKE '%catheterization%'
  GROUP BY p.subject_id
)
SELECT MIN(num_procs) AS min_procedures_per_patient
FROM procedure_counts;