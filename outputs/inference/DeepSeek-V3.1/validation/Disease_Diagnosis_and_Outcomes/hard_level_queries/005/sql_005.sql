WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    CASE
      WHEN adm.deathtime IS NOT NULL AND DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 43 AND 53
    AND (
      diag.icd_code = 'I50' AND diag.icd_version = 10
      OR
      diag.icd_code = '428' AND diag.icd_version = 9
    )
)
SELECT
  COUNT(DISTINCT hadm_id) AS cohort_size,
  SUM(mortality_30d) AS mortality_30d_count,
  ROUND(AVG(mortality_30d) * 100, 2) AS mortality_30d_percent,
  ROUND(AVG(CASE WHEN mortality_30d = 0 THEN los END), 2) AS avg_los_survivors
FROM cohort;