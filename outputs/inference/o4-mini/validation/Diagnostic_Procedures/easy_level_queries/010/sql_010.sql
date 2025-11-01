WITH echo_procs AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS echo_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` pi
      ON p.icd_code = pi.icd_code
      AND p.icd_version = pi.icd_version
  WHERE
    LOWER(pi.long_title) LIKE '%echocardi%'
  GROUP BY
    p.subject_id,
    p.hadm_id
),
male_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
      ON a.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 84 AND 94
)
SELECT
  MAX(e.echo_count) AS max_distinct_echo_per_hosp
FROM
  echo_procs e
  JOIN male_cohort m
    ON e.subject_id = m.subject_id
    AND e.hadm_id = m.hadm_id;