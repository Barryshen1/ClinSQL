WITH female_40_50 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),
mech_support_procs AS (
  SELECT p.subject_id, proc.icd_code, proc.icd_version
  FROM female_40_50 p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%mechanical circulatory support%'
)
SELECT MIN(proc_count) AS min_distinct_mech_support_procs
FROM (
  SELECT subject_id, COUNT(DISTINCT CONCAT(icd_code, '-', icd_version)) AS proc_count
  FROM mech_support_procs
  GROUP BY subject_id
);