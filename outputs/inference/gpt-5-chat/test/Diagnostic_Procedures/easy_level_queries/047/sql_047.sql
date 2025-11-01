WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 37 AND 47
),
proc_matches AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code,
    pi.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
    ON pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
  WHERE
    LOWER(dip.long_title) LIKE '%ablation%'
    OR LOWER(dip.long_title) LIKE '%cardioversion%'
),
counts_per_admission AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT CONCAT(pm.icd_code, '-', pm.icd_version)) AS distinct_proc_count
  FROM
    cohort AS c
  JOIN
    proc_matches AS pm
    ON c.hadm_id = pm.hadm_id
  GROUP BY
    c.hadm_id
)
SELECT
  STDDEV_SAMP(distinct_proc_count) AS sd_distinct_procs
FROM
  counts_per_admission;