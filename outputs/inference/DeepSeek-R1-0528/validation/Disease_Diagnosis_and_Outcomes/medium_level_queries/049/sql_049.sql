WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_adm,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    CASE 
      WHEN MAX(CASE 
                WHEN (diag.icd_version = 9 AND diag.icd_code LIKE '410%1') 
                     OR (diag.icd_version = 10 AND diag.icd_code IN ('I210','I211','I212','I213')) 
                THEN 1 ELSE 0 END) = 1 THEN 'STEMI'
      WHEN MAX(CASE 
                WHEN (diag.icd_version = 9 AND diag.icd_code LIKE '410%0') 
                     OR (diag.icd_version = 10 AND diag.icd_code = 'I214') 
                THEN 1 ELSE 0 END) = 1 THEN 'NSTEMI'
    END AS mi_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt 
      ON adm.subject_id = pt.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      ON adm.hadm_id = diag.hadm_id
  WHERE 
    pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 51 AND 61
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%') 
      OR 
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
    )
  GROUP BY 
    adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag, pt.anchor_age, pt.anchor_year
  HAVING 
    mi_type IS NOT NULL
),

comorbidities AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND (icd_code LIKE '585%' OR icd_code IN ('586', 'V420', 'V451') OR icd_code LIKE 'V56%'))
               OR (icd_version = 10 AND (icd_code LIKE 'N18%' OR icd_code = 'N19' OR icd_code LIKE 'Z49%' OR icd_code IN ('Z940', 'Z992')))
          THEN 1 ELSE 0 
        END) AS ckd_flag,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '250%')
               OR (icd_version = 10 AND icd_code LIKE 'E1%')
          THEN 1 ELSE 0 
        END) AS diabetes_flag,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '428%')
               OR (icd_version = 10 AND icd_code LIKE 'I50%')
          THEN 1 ELSE 0 
        END) AS chf_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY 
    hadm_id
),

cohort_comorbidities AS (
  SELECT 
    c.*,
    com.ckd_flag,
    com.diabetes_flag,
    com.chf_flag,
    (com.ckd_flag + com.diabetes_flag + com.chf_flag) AS comorbidity_count
  FROM 
    cohort c
    INNER JOIN comorbidities com 
      ON c.hadm_id = com.hadm_id
  WHERE 
    c.los >= 1  -- Exclude same-day discharges
)

SELECT 
  mi_type,
  CASE 
    WHEN los BETWEEN 1 AND 2 THEN '1-2'
    WHEN los BETWEEN 3 AND 5 THEN '3-5'
    WHEN los BETWEEN 6 AND 9 THEN '6-9'
    WHEN los >= 10 THEN '>=10'
  END AS los_group,
  CASE 
    WHEN comorbidity_count <= 1 THEN '0-1'
    WHEN comorbidity_count = 2 THEN '2'
    WHEN comorbidity_count >= 3 THEN '>=3'
  END AS comorbidity_group,
  COUNT(*) AS n,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percentage,
  ROUND(SUM(ckd_flag) * 100.0 / COUNT(*), 2) AS ckd_prevalence,
  ROUND(SUM(diabetes_flag) * 100.0 / COUNT(*), 2) AS diabetes_prevalence
FROM 
  cohort_comorbidities
GROUP BY 
  mi_type, los_group, comorbidity_group
ORDER BY 
  mi_type, 
  CASE los_group
    WHEN '1-2' THEN 1
    WHEN '3-5' THEN 2
    WHEN '6-9' THEN 3
    WHEN '>=10' THEN 4
  END,
  CASE comorbidity_group
    WHEN '0-1' THEN 1
    WHEN '2' THEN 2
    WHEN '>=3' THEN 3
  END;