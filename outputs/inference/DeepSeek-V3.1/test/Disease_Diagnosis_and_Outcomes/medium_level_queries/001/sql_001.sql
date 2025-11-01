WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) <= 7 THEN '<=7'
         ELSE '>7' END AS los_group,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu`.icustays icu 
      WHERE icu.hadm_id = adm.hadm_id 
      AND DATETIME_DIFF(icu.intime, adm.admittime, DAY) < 1
    ) THEN 'Yes' ELSE 'No' END AS day1_icu
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dx 
      WHERE dx.hadm_id = adm.hadm_id 
      AND dx.icd_version = 10
      AND dx.icd_code IN ('I502', 'I503', 'I504', 'I508', 'I509', 'I5020', 'I5021', 'I5022', 'I5023')
      -- Using common ADHF codes; adjust if needed
    )
),
ckd_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE icd_version = 10
    AND (icd_code LIKE 'N18%' OR icd_code LIKE 'I13%')
),
diabetes_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE icd_version = 10
    AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')
)
SELECT 
  los_group,
  day1_icu,
  COUNT(*) AS n_admissions,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  ROUND(100 * COUNT(ckd.hadm_id) / COUNT(*), 2) AS ckd_percent,
  ROUND(100 * COUNT(diab.hadm_id) / COUNT(*), 2) AS diabetes_percent
FROM cohort
LEFT JOIN ckd_patients ckd
  ON cohort.hadm_id = ckd.hadm_id
LEFT JOIN diabetes_patients diab
  ON cohort.hadm_id = diab.hadm_id
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;