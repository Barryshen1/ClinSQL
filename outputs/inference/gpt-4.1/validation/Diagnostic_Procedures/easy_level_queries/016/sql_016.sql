WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),
ecg_procedures AS (
  SELECT
    pi.hadm_id,
    pi.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pi.icd_code = dp.icd_code
      AND pi.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ecg%'
    OR LOWER(dp.long_title) LIKE '%electrocardiogram%'
    OR LOWER(dp.long_title) LIKE '%telemetry%'
    OR LOWER(dp.long_title) LIKE '%cardiac monitoring%'
)
, ecg_counts AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT ep.icd_code) AS num_ecg_procs
  FROM
    cohort c
    LEFT JOIN ecg_procedures ep
      ON c.hadm_id = ep.hadm_id
  GROUP BY
    c.hadm_id
)
SELECT
  APPROX_QUANTILES(num_ecg_procs, 4)[OFFSET(3)] AS ecg_proc_75th_percentile
FROM
  ecg_counts
;