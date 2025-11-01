WITH cohort AS (
  SELECT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),
diagnosis_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%ischemic heart disease%'
              OR LOWER(di.long_title) LIKE '%acute myocardial infarction%'
              OR di.icd_code IN ('410%', '411%', '412%', '413%', '414%', 'I20%', 'I21%', 'I22%', 'I23%', 'I24%', 'I25%') THEN 1 ELSE 0 END) AS has_ihd,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%copd%'
              OR LOWER(di.long_title) LIKE '%chronic obstructive pulmonary disease%'
              OR di.icd_code IN ('490%', '491%', '492%', '496%', 'J44%') THEN 1 ELSE 0 END) AS has_copd
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  GROUP BY
    hadm_id
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM
  cohort c
JOIN
  diagnosis_flags df
ON
  c.hadm_id = df.hadm_id
WHERE
  df.has_ihd = 1
  AND df.has_copd = 1;