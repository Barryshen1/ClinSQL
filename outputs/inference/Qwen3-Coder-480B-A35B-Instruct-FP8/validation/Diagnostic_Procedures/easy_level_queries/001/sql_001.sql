WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),
cardiac_proc_counts AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT picd.icd_code) AS distinct_cardiac_proc_count
  FROM
    cohort c
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd picd
  ON
    c.hadm_id = picd.hadm_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dproc
  ON
    picd.icd_code = dproc.icd_code
    AND picd.icd_version = dproc.icd_version
    AND LOWER(dproc.long_title) LIKE '%cardiovascular%'
  GROUP BY
    c.hadm_id
)
SELECT
  APPROX_QUANTILES(distinct_cardiac_proc_count, 100)[OFFSET(75)] AS percentile_75
FROM
  cardiac_proc_counts;