WITH male_76_86 AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),
cardiac_procs AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON pi.icd_code = d.icd_code
      AND pi.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%cardiac%'
    OR LOWER(d.long_title) LIKE '%heart%'
    OR LOWER(d.long_title) LIKE '%coronary%'
    OR LOWER(d.long_title) LIKE '%cardio%'
),
cardiac_proc_counts AS (
  SELECT
    m.hadm_id,
    COUNT(DISTINCT c.icd_code) AS num_cardiac_procs
  FROM
    male_76_86 m
    LEFT JOIN cardiac_procs c
      ON m.hadm_id = c.hadm_id
  GROUP BY
    m.hadm_id
)
SELECT
  PERCENTILE_CONT(num_cardiac_procs, 0.25) OVER() AS cardiac_proc_count_25th_percentile,
  PERCENTILE_CONT(num_cardiac_procs, 0.75) OVER() AS cardiac_proc_count_75th_percentile
FROM
  cardiac_proc_counts
LIMIT 1;