WITH cabg_procedures AS (
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    LOWER(long_title) LIKE '%coronary artery bypass graft%'
),
per_patient_cabg_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT p.icd_code) AS cabg_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    cabg_procedures c
  ON
    p.icd_code = c.icd_code
    AND p.icd_version = c.icd_version
  GROUP BY
    p.subject_id
),
male_45_55 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 45 AND 55
)
SELECT
  -- APPROX_QUANTILES returns an array of quantile cutpoints; [OFFSET(25)] is the 25th percentile
  APPROX_QUANTILES(coalesced_counts.cabg_count, 100)[OFFSET(25)] AS p25_cabg_per_patient
FROM (
  SELECT
    m.subject_id,
    COALESCE(c.cabg_count, 0) AS cabg_count
  FROM
    male_45_55 m
  LEFT JOIN
    per_patient_cabg_counts c
  ON
    m.subject_id = c.subject_id
) AS coalesced_counts;