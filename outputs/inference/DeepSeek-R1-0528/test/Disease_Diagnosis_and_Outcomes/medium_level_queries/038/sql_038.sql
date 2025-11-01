WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 80 AND 90
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

icu_status AS (
  SELECT 
    c.hadm_id,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status
  FROM cohort c
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON c.hadm_id = i.hadm_id
),

ckd_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (
        icd_code LIKE '585%' OR 
        icd_code LIKE '586%' OR 
        icd_code LIKE 'V56%' OR 
        icd_code LIKE '403%' OR 
        icd_code LIKE '404%'
    )) OR 
    (icd_version = 10 AND (
        icd_code LIKE 'N18%' OR 
        icd_code LIKE 'N19%' OR 
        icd_code LIKE 'I12%' OR 
        icd_code LIKE 'I13%' OR 
        icd_code LIKE 'Z49%' OR 
        icd_code = 'Z99.2'
    ))
),

diabetes_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%') OR 
    (icd_version = 10 AND (
        icd_code LIKE 'E10%' OR 
        icd_code LIKE 'E11%' OR 
        icd_code LIKE 'E12%' OR 
        icd_code LIKE 'E13%' OR 
        icd_code LIKE 'E14%'
    ))
),

cohort_with_flags AS (
  SELECT 
    c.*,
    icu.icu_status,
    CASE WHEN ckd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS ckd_flag,
    CASE WHEN dm.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS diabetes_flag,
    CASE WHEN c.los_days < 8 THEN '<8' ELSE '>=8' END AS los_group
  FROM cohort c
  INNER JOIN icu_status icu ON c.hadm_id = icu.hadm_id
  LEFT JOIN ckd_patients ckd ON c.hadm_id = ckd.hadm_id
  LEFT JOIN diabetes_patients dm ON c.hadm_id = dm.hadm_id
)

SELECT 
  icu_status,
  los_group,
  COUNT(hadm_id) AS total_admissions,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(hadm_id), 2) AS mortality_percent,
  ROUND(100 * SUM(ckd_flag) / COUNT(hadm_id), 2) AS ckd_percent,
  ROUND(100 * SUM(diabetes_flag) / COUNT(hadm_id), 2) AS diabetes_percent
FROM cohort_with_flags
GROUP BY icu_status, los_group
ORDER BY icu_status, los_group;