WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
proc_ablation_cardioversion AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.icd_code,
    pr.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
      ON pr.icd_code = dpr.icd_code
      AND pr.icd_version = dpr.icd_version
  WHERE
    LOWER(dpr.long_title) LIKE '%catheter ablation%'
    OR LOWER(dpr.long_title) LIKE '%cardioversion%'
),
hadm_proc_counts AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT p.icd_code) AS num_distinct_procs
  FROM
    cohort c
    LEFT JOIN proc_ablation_cardioversion p
      ON c.hadm_id = p.hadm_id
  GROUP BY
    c.hadm_id
)
SELECT
  STDDEV(num_distinct_procs) AS sd_distinct_procs_per_hadm
FROM
  hadm_proc_counts
;