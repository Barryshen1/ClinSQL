WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),
mech_support_procs AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
    ON pi.icd_code = dp.icd_code
    AND pi.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ventricular assist%'
    OR LOWER(dp.long_title) LIKE '%ecmo%'
    OR LOWER(dp.long_title) LIKE '%intra-aortic balloon%'
)
, proc_counts AS (
  SELECT
    ca.hadm_id,
    COUNT(DISTINCT msp.icd_code) AS proc_count
  FROM
    cohort_admissions AS ca
  LEFT JOIN
    mech_support_procs AS msp
    USING(subject_id, hadm_id)
  GROUP BY
    ca.hadm_id
)
SELECT
  quartiles[OFFSET(1)] AS q1,
  quartiles[OFFSET(3)] AS q3,
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS iqr
FROM (
  SELECT
    APPROX_QUANTILES(proc_count, 4) AS quartiles
  FROM
    proc_counts
);