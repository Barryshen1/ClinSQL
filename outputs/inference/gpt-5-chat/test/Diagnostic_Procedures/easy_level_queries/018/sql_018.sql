WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),
proc_matches AS (
  SELECT DISTINCT p.subject_id, pi.icd_code, pi.icd_version
  FROM cohort p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON p.subject_id = pi.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi
    ON pi.icd_code = dpi.icd_code
   AND pi.icd_version = dpi.icd_version
  WHERE LOWER(dpi.long_title) LIKE '%catheter ablation%'
     OR LOWER(dpi.long_title) LIKE '%cardioversion%'
),
counts_per_patient AS (
  SELECT subject_id,
         COUNT(DISTINCT CONCAT(icd_code, '-', icd_version)) AS distinct_proc_count
  FROM proc_matches
  GROUP BY subject_id
)
SELECT STDDEV_SAMP(distinct_proc_count) AS sd_distinct_proc_per_patient
FROM counts_per_patient;