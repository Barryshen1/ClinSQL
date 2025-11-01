WITH hf_hadm AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND (
      (di.icd_version = 9  AND di.icd_code LIKE '428%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
),

hf_pop AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.deathtime,
    h.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, SECOND) / 86400.0 AS los_days
  FROM hf_hadm AS h
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.subject_id = h.subject_id AND i.hadm_id = h.hadm_id
),

hadm_metrics AS (
  SELECT
    f.hadm_id,
    f.subject_id,
    f.icu_group,
    f.los_days,
    MAX(CASE
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%')
               OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
          THEN 1 ELSE 0
        END) AS ckd_present,
    MAX(CASE
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%')
               OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%'))
          THEN 1 ELSE 0
        END) AS dia_present,
    (COUNT(DISTINCT d.icd_code) - 1) AS comorb_count,
    CASE WHEN (f.deathtime IS NOT NULL OR f.hospital_expire_flag = 1) THEN 1 ELSE 0 END AS mortality_flag
  FROM hf_pop AS f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = f.subject_id AND d.hadm_id = f.hadm_id
  GROUP BY
    f.hadm_id, f.subject_id, f.icu_group, f.los_days, f.deathtime, f.hospital_expire_flag
)

SELECT
  icu_group,
  CASE WHEN los_days < 8.0 THEN '<8' ELSE '>=8' END AS los_cat,
  CASE
    WHEN comorb_count <= 1 THEN '0-1'
    WHEN comorb_count = 2 THEN '2'
    ELSE '>=3'
  END AS comorb_cat,
  100.0 * SUM(mortality_flag) / COUNT(*) AS mortality_percent,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  100.0 * SUM(ckd_present) / COUNT(*) AS ckd_prevalence_percent,
  100.0 * SUM(dia_present) / COUNT(*) AS diabetes_prevalence_percent
FROM hadm_metrics
GROUP BY icu_group, los_cat, comorb_cat
ORDER BY icu_group, comorb_cat, los_cat;