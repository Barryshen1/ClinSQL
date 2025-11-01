WITH sepsis_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    -- length of stay in days, floating
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 64 AND 74
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE (
        (icd_version = 9 AND (
            icd_code LIKE '038%' OR
            icd_code = '99591' OR icd_code = '99592'
        ))
        OR
        (icd_version = 10 AND (
            icd_code LIKE 'A40%' OR
            icd_code LIKE 'A41%'
        ))
      )
      AND NOT (
        (icd_version = 9 AND icd_code = '78552')
        OR (icd_version = 10 AND (icd_code = 'R6521' OR icd_code = 'R65.21'))
      )
    )
),
comorbidities AS (
  SELECT
    hadm_id,
    MAX(CASE
      WHEN (icd_version = 9 AND (icd_code LIKE '585%' OR icd_code = '586'))
        OR (icd_version = 10 AND icd_code LIKE 'N18%')
      THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE
      WHEN (icd_version = 9 AND (icd_code LIKE '250%' OR icd_code LIKE '249%'))
        OR (icd_version = 10 AND (
            icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR
            icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR
            icd_code LIKE 'E14%'
        ))
      THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_with_comorb AS (
  SELECT
    s.*,
    IFNULL(c.has_ckd,0) AS has_ckd,
    IFNULL(c.has_diabetes,0) AS has_diabetes
  FROM sepsis_cohort s
  LEFT JOIN comorbidities c
    ON s.hadm_id = c.hadm_id
),
quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM cohort_with_comorb
)
SELECT
  los_quartile,
  COUNT(*) AS admissions,
  ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 1) AS mortality_rate_pct,
  ROUND(SUM(has_ckd) / COUNT(*) * 100, 1) AS ckd_prevalence_pct,
  ROUND(SUM(has_diabetes) / COUNT(*) * 100, 1) AS diabetes_prevalence_pct
FROM quartiled
GROUP BY los_quartile
ORDER BY los_quartile;