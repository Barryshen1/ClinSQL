WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),
cardiac_counts AS (
  SELECT
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS cnt
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON proc.icd_code = d.icd_code
      AND proc.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%cardiac%'
  GROUP BY
    proc.hadm_id
)
SELECT
  APPROX_QUANTILES(COALESCE(c.cnt, 0), 4)[OFFSET(3)] AS percentile_75th_distinct_cardiac_procs
FROM
  cohort co
  LEFT JOIN cardiac_counts c
    ON co.hadm_id = c.hadm_id;