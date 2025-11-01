WITH adm_dx AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    -- Flag if any diagnosis in this admission is ADHF
    MAX(CASE 
      WHEN LOWER(diag.long_title) LIKE '%decompensated heart failure%' 
        OR LOWER(diag.long_title) LIKE '%acute heart failure%' 
        OR LOWER(diag.long_title) LIKE '%heart failure, decompensated%'
        THEN 1 ELSE 0 END) AS has_adhf,
    -- Flag CKD
    MAX(CASE 
      WHEN LOWER(diag.long_title) LIKE '%chronic kidney disease%' 
        OR LOWER(diag.long_title) LIKE '%ckd%' 
        OR (icd.icd_version = 10 AND SUBSTR(icd.icd_code, 1, 3) = 'N18')
        THEN 1 ELSE 0 END) AS has_ckd,
    -- Flag diabetes
    MAX(CASE 
      WHEN LOWER(diag.long_title) LIKE '%diabetes%' 
        OR (icd.icd_version = 10 AND SUBSTR(icd.icd_code, 1, 3) = 'E11')
        OR (icd.icd_version = 10 AND SUBSTR(icd.icd_code, 1, 3) = 'E10')
        THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd
    ON a.hadm_id = icd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON icd.icd_code = diag.icd_code AND icd.icd_version = diag.icd_version
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
patient_filtered AS (
  SELECT
    adm_dx.*
  FROM adm_dx
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm_dx.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND adm_dx.has_adhf = 1
),
icu_day1 AS (
  SELECT DISTINCT
    pf.subject_id,
    pf.hadm_id,
    pf.admittime,
    pf.dischtime,
    pf.hospital_expire_flag,
    pf.los_days,
    pf.has_ckd,
    pf.has_diabetes,
    1 AS icu_day1
  FROM patient_filtered pf
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pf.hadm_id = icu.hadm_id
  WHERE icu.intime < DATETIME_ADD(pf.admittime, INTERVAL 1 DAY)
    AND icu.outtime >= pf.admittime
),
no_icu_day1 AS (
  SELECT
    pf.subject_id,
    pf.hadm_id,
    pf.admittime,
    pf.dischtime,
    pf.hospital_expire_flag,
    pf.los_days,
    pf.has_ckd,
    pf.has_diabetes,
    0 AS icu_day1
  FROM patient_filtered pf
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    WHERE icu.hadm_id = pf.hadm_id
      AND icu.intime < DATETIME_ADD(pf.admittime, INTERVAL 1 DAY)
      AND icu.outtime >= pf.admittime
  )
),
combined AS (
  SELECT * FROM icu_day1
  UNION ALL
  SELECT * FROM no_icu_day1
),
stratified AS (
  SELECT
    icu_day1,
    CASE WHEN los_days <= 7 THEN '≤7' ELSE '>7' END AS los_group,
    hospital_expire_flag,
    has_ckd,
    has_diabetes
  FROM combined
)
SELECT
  los_group,
  icu_day1,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_pct,
  AVG(has_ckd) * 100 AS ckd_prevalence_pct,
  AVG(has_diabetes) * 100 AS diabetes_prevalence_pct
FROM stratified
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;