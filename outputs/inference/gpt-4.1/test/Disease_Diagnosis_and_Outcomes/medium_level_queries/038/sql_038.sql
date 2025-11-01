WITH cohort AS (
  -- Select admissions for females age 80-90 with heart failure
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender,
    -- Calculate LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS FLOAT64) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND (
      -- Heart failure ICD-10: I50.x, ICD-9: 428.x
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
      OR
      (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
    )
),
icu_flags AS (
  -- Flag admissions with any ICU stay
  SELECT DISTINCT
    hadm_id,
    1 AS had_icu
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),
ckd_flags AS (
  -- Flag admissions with CKD diagnosis
  SELECT DISTINCT
    hadm_id,
    1 AS has_ckd
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 10 AND icd_code LIKE 'N18%')
    OR
    (icd_version = 9 AND icd_code LIKE '585%')
),
dm_flags AS (
  -- Flag admissions with diabetes diagnosis
  SELECT DISTINCT
    hadm_id,
    1 AS has_dm
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 10 AND (
      icd_code LIKE 'E10%' OR
      icd_code LIKE 'E11%' OR
      icd_code LIKE 'E12%' OR
      icd_code LIKE 'E13%' OR
      icd_code LIKE 'E14%'
    ))
    OR
    (icd_version = 9 AND icd_code LIKE '250%')
),
final AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    IFNULL(i.had_icu, 0) AS had_icu,
    c.hospital_expire_flag,
    IFNULL(ckd.has_ckd, 0) AS has_ckd,
    IFNULL(dm.has_dm, 0) AS has_dm
  FROM
    cohort c
    LEFT JOIN icu_flags i ON c.hadm_id = i.hadm_id
    LEFT JOIN ckd_flags ckd ON c.hadm_id = ckd.hadm_id
    LEFT JOIN dm_flags dm ON c.hadm_id = dm.hadm_id
)
SELECT
  CASE
    WHEN had_icu = 1 AND los_days < 8 THEN 'ICU, LOS <8'
    WHEN had_icu = 1 AND los_days >= 8 THEN 'ICU, LOS ≥8'
    WHEN had_icu = 0 AND los_days < 8 THEN 'Non-ICU, LOS <8'
    WHEN had_icu = 0 AND los_days >= 8 THEN 'Non-ICU, LOS ≥8'
    ELSE 'Other'
  END AS group_label,
  COUNT(*) AS n_admissions,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percent,
  ROUND(100 * SUM(CASE WHEN has_ckd = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS ckd_percent,
  ROUND(100 * SUM(CASE WHEN has_dm = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS diabetes_percent
FROM
  final
GROUP BY
  group_label
ORDER BY
  group_label;