WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),
cardiac_counts AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS cardiac_proc_count
  FROM
    cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
      ON c.hadm_id = pi.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
      ON pi.icd_code = dp.icd_code
     AND pi.icd_version = dp.icd_version
     AND LOWER(dp.long_title) LIKE '%cardiac%'
  GROUP BY
    c.hadm_id
)
SELECT
  quartiles[OFFSET(1)] AS q1,
  quartiles[OFFSET(3)] AS q3,
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS iqr
FROM (
  SELECT
    APPROX_QUANTILES(cardiac_proc_count, 4) AS quartiles
  FROM
    cardiac_counts
);