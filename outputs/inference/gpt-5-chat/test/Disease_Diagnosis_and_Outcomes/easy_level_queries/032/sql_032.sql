WITH aki_male_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%') -- ICD-9 AKI
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%') -- ICD-10 AKI
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  quantiles[OFFSET(1)] AS q1_los_days,
  quantiles[OFFSET(3)] AS q3_los_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_los_days
FROM (
  SELECT
    APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM aki_male_admissions
);