WITH cohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),
echo_codes AS (
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    LOWER(long_title) LIKE '%echocardi%'
),
patient_echo_counts AS (
  SELECT
    c.subject_id,
    COUNT(DISTINCT pi.icd_code) AS echo_proc_count
  FROM
    cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
      ON c.subject_id = pi.subject_id
    LEFT JOIN echo_codes AS ec
      ON pi.icd_code = ec.icd_code
     AND pi.icd_version = ec.icd_version
  GROUP BY
    c.subject_id
)
SELECT
  APPROX_QUANTILES(echo_proc_count, 100)[OFFSET(25)] AS p25_echo_per_patient
FROM
  patient_echo_counts;