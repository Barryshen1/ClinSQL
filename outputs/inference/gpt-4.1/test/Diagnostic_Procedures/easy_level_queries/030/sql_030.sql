WITH female_84_94 AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),
echo_procedures AS (
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    LOWER(long_title) LIKE '%echocardiography%'
),
hadm_echo_counts AS (
  SELECT
    f.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS num_echo_procs
  FROM
    female_84_94 f
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      ON f.hadm_id = pi.hadm_id
    LEFT JOIN echo_procedures ep
      ON pi.icd_code = ep.icd_code AND pi.icd_version = ep.icd_version
  WHERE
    ep.icd_code IS NOT NULL
  GROUP BY
    f.hadm_id
)
SELECT
  PERCENTILE_CONT(num_echo_procs, 0.25) OVER() AS echo_proc_25th_percentile
FROM
  hadm_echo_counts
;