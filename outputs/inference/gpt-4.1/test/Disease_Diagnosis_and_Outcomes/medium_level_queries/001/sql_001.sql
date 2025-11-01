WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 67 AND 77
),
adhf_admissions AS (
  -- ADHF ICD codes (ICD-9: 428.21, 428.23, 428.31, 428.33; ICD-10: I50.21, I50.23, I50.31, I50.33, I50.41, I50.43)
  SELECT DISTINCT
    c.*
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON c.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-9
      (dx.icd_version = 9 AND dx.icd_code IN ('42821','42823','42831','42833'))
      OR
      -- ICD-10
      (dx.icd_version = 10 AND dx.icd_code IN ('I5021','I5023','I5031','I5033','I5041','I5043'))
    )
),
ckd_flags AS (
  -- CKD ICD codes (ICD-9: 585.x; ICD-10: N18.x)
  SELECT
    hadm_id,
    1 AS has_ckd
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^585'))
    OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N18'))
  GROUP BY hadm_id
),
diabetes_flags AS (
  -- Diabetes ICD codes (ICD-9: 250.x; ICD-10: E10.x, E11.x, E13.x)
  SELECT
    hadm_id,
    1 AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250'))
    OR
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^E10') OR
      REGEXP_CONTAINS(icd_code, r'^E11') OR
      REGEXP_CONTAINS(icd_code, r'^E13')
    ))
  GROUP BY hadm_id
),
icu_day1 AS (
  -- ICU stay overlaps with day 1 of admission
  SELECT
    icu.hadm_id,
    1 AS day1_icu
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.hadm_id = adm.hadm_id
  WHERE
    icu.intime < DATETIME_ADD(adm.admittime, INTERVAL 1 DAY)
    AND icu.outtime > adm.admittime
  GROUP BY icu.hadm_id
),
final AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_days,
    CASE WHEN a.los_days <= 7 THEN '<=7' ELSE '>7' END AS los_group,
    IFNULL(i.day1_icu, 0) AS day1_icu,
    a.hospital_expire_flag,
    IFNULL(c.has_ckd, 0) AS has_ckd,
    IFNULL(d.has_diabetes, 0) AS has_diabetes
  FROM
    adhf_admissions a
    LEFT JOIN ckd_flags c ON a.hadm_id = c.hadm_id
    LEFT JOIN diabetes_flags d ON a.hadm_id = d.hadm_id
    LEFT JOIN icu_day1 i ON a.hadm_id = i.hadm_id
)
SELECT
  los_group,
  day1_icu,
  COUNT(*) AS n_admissions,
  ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(SUM(has_ckd) / COUNT(*) * 100, 2) AS ckd_prevalence_pct,
  ROUND(SUM(has_diabetes) / COUNT(*) * 100, 2) AS diabetes_prevalence_pct
FROM
  final
GROUP BY
  los_group,
  day1_icu
ORDER BY
  los_group,
  day1_icu DESC;