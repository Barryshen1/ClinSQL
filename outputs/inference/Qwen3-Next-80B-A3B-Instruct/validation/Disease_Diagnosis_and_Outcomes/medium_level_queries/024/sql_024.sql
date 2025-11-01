WITH sepsis_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      -- Sepsis without septic shock: include
      (d.icd_version = 9 AND d.icd_code = '995.91')
      OR
      (d.icd_version = 10 AND d.icd_code IN ('A41.9', 'R65.20'))
    )
    -- Exclude septic shock
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did2
        ON d2.icd_code = did2.icd_code AND d2.icd_version = did2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 9 AND d2.icd_code = '995.92')
          OR
          (d2.icd_version = 10 AND d2.icd_code = 'R65.21')
        )
    )
),
diabetes_ckd_flags AS (
  SELECT
    hadm_id,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '250.%')
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%'))
      THEN 1 ELSE 0 END) AS diabetes_flag,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '585.%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
      THEN 1 ELSE 0 END) AS ckd_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY hadm_id
),
icu_day1_flag AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN intime BETWEEN admittime AND admittime + INTERVAL '24 hours' THEN 1 ELSE 0 END) AS day1_icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  GROUP BY hadm_id
),
cohort AS (
  SELECT
    sp.subject_id,
    sp.hadm_id,
    sp.admittime,
    sp.dischtime,
    sp.hospital_expire_flag,
    sp.anchor_age,
    sp.gender,
    COALESCE(dcf.diabetes_flag, 0) AS diabetes_flag,
    COALESCE(dcf.ckd_flag, 0) AS ckd_flag,
    COALESCE(idf.day1_icu_flag, 0) AS day1_icu_flag,
    EXTRACT(DAY FROM (sp.dischtime - sp.admittime)) AS los_days
  FROM sepsis_patients sp
  LEFT JOIN diabetes_ckd_flags dcf ON sp.hadm_id = dcf.hadm_id
  LEFT JOIN icu_day1_flag idf ON sp.hadm_id = idf.hadm_id
)
SELECT
  CASE WHEN los_days <= 5 THEN 'LOS <=5' ELSE 'LOS >5' END AS los_group,
  CASE WHEN day1_icu_flag = 1 THEN 'Day-1 ICU' ELSE 'Non-ICU' END AS icu_group,
  COUNT(*) AS N,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  AVG(diabetes_flag) * 100 AS diabetes_prevalence_percent,
  AVG(ckd_flag) * 100 AS ckd_prevalence_percent
FROM cohort
GROUP BY los_group, icu_group
ORDER BY los_group, icu_group;