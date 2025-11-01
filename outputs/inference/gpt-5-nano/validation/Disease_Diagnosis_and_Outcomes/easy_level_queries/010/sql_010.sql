WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS din
    ON di.icd_code = din.icd_code
   AND di.icd_version = din.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND di.seq_num = 1
    AND (
      LOWER(din.long_title) LIKE '%copd%'
      OR LOWER(din.long_title) LIKE '%chronic obstructive pulmonary disease%'
      OR LOWER(din.long_title) LIKE '%exacerbation%'
    )
    AND a.dischtime IS NOT NULL
)
SELECT
  quantiles[OFFSET(24)] AS p25_los_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM cohort
);