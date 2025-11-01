WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
),
catheter_proc AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.icd_code,
    pr.icd_version,
    d.long_title
  FROM cohort p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  WHERE UPPER(d.long_title) LIKE '%CARDIAC CATH%'
    AND UPPER(d.long_title) LIKE '%DIAGNOSTIC%'
)
, counts_per_patient AS (
  SELECT subject_id, COUNT(*) AS num_catheterizations
  FROM catheter_proc
  GROUP BY subject_id
)
SELECT MIN(num_catheterizations) AS min_catheterizations_per_patient
FROM counts_per_patient;