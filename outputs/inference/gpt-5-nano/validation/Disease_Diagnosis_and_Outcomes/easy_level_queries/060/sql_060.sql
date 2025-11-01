with ugib_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
    ON dicd.icd_code = di.icd_code
   AND dicd.icd_version = di.icd_version
  WHERE di.seq_num = 1
    AND LOWER(dicd.long_title) LIKE '%upper%'
    AND (LOWER(dicd.long_title) LIKE '%bleed%' OR LOWER(dicd.long_title) LIKE '%hemorrhage%')
    AND a.dischtime IS NOT NULL
),
filtered AS (
  SELECT
    ug.hadm_id,
    ug.subject_id,
    ug.admittime,
    ug.dischtime,
    TIMESTAMP_DIFF(ug.dischtime, ug.admittime, SECOND) / 86400.0 AS los_days
  FROM ugib_admissions AS ug
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = ug.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 74 AND 84
)
SELECT
  q[OFFSET(25)] AS los_25th_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 100) AS q
  FROM filtered
) AS quantiles;