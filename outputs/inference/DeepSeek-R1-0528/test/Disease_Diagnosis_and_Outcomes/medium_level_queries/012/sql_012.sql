WITH cohort AS (
  SELECT DISTINCT
    adm.hadm_id,
    adm.subject_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission: (admittime year) - (anchor_year - anchor_age)
    CAST(EXTRACT(YEAR FROM adm.admittime) AS INT64) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    -- Calculate hospital LOS in days
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON adm.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      ON adm.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'F'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '428%') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
    )
    -- Filter for age 83-93 at admission
    AND (CAST(EXTRACT(YEAR FROM adm.admittime) AS INT64) - (p.anchor_year - p.anchor_age)) BETWEEN 83 AND 93
),

comorbidities AS (
  SELECT
    c.hadm_id,
    -- Comorbidity burden (count of: hypertension, obesity, atrial fibrillation)
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '401%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'I1[0-5]%') 
         THEN 1 ELSE 0 END) AS hypertension,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code = '278.0') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'E66%') 
         THEN 1 ELSE 0 END) AS obesity,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code = '427.31') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'I48%') 
         THEN 1 ELSE 0 END) AS afib,
    -- Conditions to report separately (CKD and diabetes)
    MAX(CASE 
          WHEN (d.icd_version = 9 AND (d.icd_code LIKE '58[5-8]%' OR d.icd_code LIKE 'V42.0' OR d.icd_code LIKE 'V45.1' OR d.icd_code LIKE 'V56%')) 
             OR (d.icd_version = 10 AND (d.icd_code LIKE 'N1[89]%' OR d.icd_code LIKE 'I1[23]%' OR d.icd_code LIKE 'N25%' OR d.icd_code LIKE 'Z49%' OR d.icd_code = 'Z94.0' OR d.icd_code = 'Z99.2')) 
         THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'E1[0-4]%') 
         THEN 1 ELSE 0 END) AS diabetes_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.hadm_id = d.hadm_id
  GROUP BY c.hadm_id
),

icu_flag AS (
  SELECT
    c.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_group
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON c.hadm_id = i.hadm_id
)

SELECT
  icu.icu_group,
  CASE 
    WHEN c.los_days < 8 THEN '<8' 
    ELSE '>=8' 
  END AS los_group,
  CASE
    WHEN (com.hypertension + com.obesity + com.afib) <= 1 THEN '0-1'
    WHEN (com.hypertension + com.obesity + com.afib) = 2 THEN '2'
    ELSE '>=3' 
  END AS comorbidity_burden,
  COUNT(*) AS admissions,
  ROUND(AVG(c.hospital_expire_flag) * 100, 2) AS mortality_percentage,
  ROUND(APPROX_QUANTILES(c.los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  ROUND(AVG(com.ckd_flag) * 100, 2) AS ckd_prevalence,
  ROUND(AVG(com.diabetes_flag) * 100, 2) AS diabetes_prevalence
FROM cohort c
INNER JOIN comorbidities com 
  ON c.hadm_id = com.hadm_id
INNER JOIN icu_flag icu 
  ON c.hadm_id = icu.hadm_id
GROUP BY 
  icu_group, 
  los_group, 
  comorbidity_burden
ORDER BY 
  icu_group, 
  los_group, 
  comorbidity_burden;