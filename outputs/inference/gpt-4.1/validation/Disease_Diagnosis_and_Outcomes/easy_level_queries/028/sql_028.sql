WITH female_aged_67_77 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 67 AND 77
),
pneumonia_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    diag.icd_code,
    diag.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN female_aged_67_77 f
    ON adm.subject_id = f.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE diag.seq_num = 1
    AND (
      -- ICD-10 pneumonia: J13-J18
      (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^J1[3-8]'))
      -- ICD-9 pneumonia: 480-486
      OR (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^48[0-6]'))
    )
),
los_days AS (
  SELECT
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM pneumonia_admissions
  WHERE admittime IS NOT NULL
    AND dischtime IS NOT NULL
    AND DATETIME_DIFF(dischtime, admittime, DAY) > 0
)
SELECT
  quantiles[OFFSET(1)] AS los_25th_percentile_days
FROM (
  SELECT APPROX_QUANTILES(los, 4) AS quantiles
  FROM los_days
);