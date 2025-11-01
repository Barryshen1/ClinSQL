WITH comorbidity_codes AS (
  SELECT icd_code, icd_version, long_title
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%diabetes%' 
     OR LOWER(long_title) LIKE '%chronic kidney disease%'
     OR LOWER(long_title) LIKE '%renal failure%'
     OR LOWER(long_title) LIKE '%lymphoma%'
     OR LOWER(long_title) LIKE '%cancer%'
     OR LOWER(long_title) LIKE '%metastatic%'
     OR LOWER(long_title) LIKE '%dementia%'
     OR LOWER(long_title) LIKE '%chronic pulmonary%'
     OR LOWER(long_title) LIKE '%peptic ulcer%'
     OR LOWER(long_title) LIKE '%rheumatoid arthritis%'
     OR LOWER(long_title) LIKE '%mild liver%'
     OR LOWER(long_title) LIKE '%moderate or severe liver%'
     OR LOWER(long_title) LIKE '%hemiplegia%'
     OR LOWER(long_title) LIKE '%paraplegia%'
     OR LOWER(long_title) LIKE '%heart failure%'
     OR LOWER(long_title) LIKE '%myocardial infarction%'
     OR LOWER(long_title) LIKE '%cerebrovascular%'
     OR LOWER(long_title) LIKE '%peripheral vascular%'
     OR LOWER(long_title) LIKE '%diabetes%'
     OR LOWER(long_title) LIKE '%renal%'
     OR LOWER(long_title) LIKE '%diabetic%'
),
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%heart failure%'
     OR LOWER(long_title) LIKE '%congestive heart failure%'
     OR LOWER(long_title) LIKE '%systolic heart failure%'
     OR LOWER(long_title) LIKE '%diastolic heart failure%'
),
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender, p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
),
first_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_of_interest p ON a.subject_id = p.subject_id
),
hf_admissions AS (
  SELECT fa.*
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON fa.hadm_id = di.hadm_id
  INNER JOIN heart_failure_codes hfc
    ON di.icd_code = hfc.icd_code AND di.icd_version = hfc.icd_version
  WHERE fa.rn = 1
),
comorbidity_counts AS (
  SELECT di.hadm_id,
         COUNT(DISTINCT cc.icd_code) AS comorbidity_count,
         MAX(CASE WHEN LOWER(cc.long_title) LIKE '%chronic kidney disease%' 
               OR LOWER(cc.long_title) LIKE '%renal failure%' THEN 1 ELSE 0 END) AS has_ckd,
         MAX(CASE WHEN LOWER(cc.long_title) LIKE '%diabetes%' 
               OR LOWER(cc.long_title) LIKE '%diabetic%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN comorbidity_codes cc ON di.icd_code = cc.icd_code AND di.icd_version = cc.icd_version
  INNER JOIN hf_admissions hfa ON di.hadm_id = hfa.hadm_id
  GROUP BY di.hadm_id
),
admissions_with_los_comorb AS (
  SELECT hfa.*,
         cc.comorbidity_count,
         cc.has_ckd,
         cc.has_diabetes,
         DATETIME_DIFF(hfa.dischtime, hfa.admittime, DAY) AS los_days
  FROM hf_admissions hfa
  LEFT JOIN comorbidity_counts cc ON hfa.hadm_id = cc.hadm_id
),
comorbidity_tertiles AS (
  SELECT *,
         NTILE(3) OVER (ORDER BY comorbidity_count) AS tertile_group
  FROM admissions_with_los_comorb
),
final_cohort AS (
  SELECT *,
         CASE WHEN los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_group
  FROM comorbidity_tertiles
)
SELECT 
  los_group,
  CASE tertile_group
    WHEN 1 THEN 'Low'
    WHEN 2 THEN 'Medium'
    ELSE 'High'
  END AS comorbidity_burden,
  COUNT(*) AS N,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
  AVG(has_ckd) * 100 AS ckd_prevalence_percent,
  AVG(has_diabetes) * 100 AS diabetes_prevalence_percent
FROM final_cohort
GROUP BY los_group, comorbidity_burden
ORDER BY los_group, comorbidity_burden;