WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
   AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON di.icd_code = did.icd_code
   AND di.icd_version = did.icd_version
  WHERE (
          LOWER(p.gender) IN ('f', 'female')
        )
    AND a.dischtime IS NOT NULL
    AND (
          LOWER(did.long_title) LIKE '%sepsis%'
          OR LOWER(did.long_title) LIKE '%septic%'
          OR di.icd_code LIKE 'A41%'
          OR di.icd_code LIKE 'R65%'
          OR di.icd_code LIKE '038%'
          OR di.icd_code LIKE '785.5%'
        )
    AND (
          (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 40 AND 50
        )
)

SELECT
  quantiles[OFFSET(1)] AS q1_days,
  quantiles[OFFSET(3)] AS q3_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM filtered_admissions
  WHERE los_days IS NOT NULL
) AS q;