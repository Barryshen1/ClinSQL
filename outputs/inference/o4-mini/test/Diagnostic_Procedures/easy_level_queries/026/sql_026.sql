WITH patient_procs AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pi.icd_code) AS proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
      ON p.subject_id = pi.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
      ON pi.icd_code = dp.icd_code
      AND pi.icd_version = dp.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND (
      LOWER(dp.long_title) LIKE '%ablation%'
      OR LOWER(dp.long_title) LIKE '%cardioversion%'
    )
  GROUP BY
    p.subject_id
)

SELECT
  quantiles[OFFSET(1)] AS q1,
  quantiles[OFFSET(3)] AS q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM (
  SELECT
    APPROX_QUANTILES(proc_count, 4) AS quantiles
  FROM
    patient_procs
);