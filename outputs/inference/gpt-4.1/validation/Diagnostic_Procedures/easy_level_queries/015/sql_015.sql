WITH male_45_55 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 45 AND 55
),
cabg_procs AS (
  SELECT
    p.subject_id,
    proc.icd_code
  FROM male_45_55 p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE
    LOWER(dproc.long_title) LIKE '%bypass%'
    AND LOWER(dproc.long_title) LIKE '%coronary%'
)
, cabg_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS num_cabg_procs
  FROM cabg_procs
  GROUP BY subject_id
)
SELECT
  PERCENTILE_CONT(num_cabg_procs, 0.25) OVER() AS cabg_25th_percentile
FROM cabg_counts
;