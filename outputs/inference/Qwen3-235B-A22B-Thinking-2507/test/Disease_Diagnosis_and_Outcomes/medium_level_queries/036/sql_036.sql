WITH hf_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN hf_diagnoses h
    ON a.hadm_id = h.hadm_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 39 AND 49
),
condition_flags AS (
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%')) 
         THEN 1 ELSE 0 END) AS diabetes_flag,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '585%' OR d.icd_code IN ('586','V420','V451') OR d.icd_code LIKE 'V56%')) 
              OR (d.icd_version = 10 AND d.icd_code IN ('N181','N182','N183','N184','N185','N186','Z490','Z491','Z492','Z493','Z940','Z992')) 
         THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '401%' OR d.icd_code LIKE '402%' OR d.icd_code LIKE '403%' OR d.icd_code LIKE '404%' OR d.icd_code LIKE '405%'))
              OR (d.icd_version = 10 AND (d.icd_code = 'I10' OR d.icd_code LIKE 'I11%' OR d.icd_code LIKE 'I12%' OR d.icd_code LIKE 'I13%' OR d.icd_code LIKE 'I15%'))
         THEN 1 ELSE 0 END) AS hypertension_flag,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code = '42731')
              OR (d.icd_version = 10 AND d.icd_code IN ('I480','I481','I482','I483','I484','I489'))
         THEN 1 ELSE 0 END) AS afib_flag,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '490%' OR d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '493%' OR d.icd_code LIKE '494%' OR d.icd_code LIKE '495%' OR d.icd_code LIKE '496%' OR d.icd_code LIKE '500%' OR d.icd_code LIKE '501%' OR d.icd_code LIKE '502%' OR d.icd_code LIKE '503%' OR d.icd_code LIKE '504%' OR d.icd_code LIKE '505%' OR d.icd_code = '5064' OR d.icd_code = '5081' OR d.icd_code = '51883'))
              OR (d.icd_version = 10 AND (d.icd_code = 'J40' OR d.icd_code LIKE 'J41%' OR d.icd_code = 'J42' OR d.icd_code LIKE 'J43%' OR d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J45%' OR d.icd_code LIKE 'J46%' OR d.icd_code LIKE 'J47%' OR d.icd_code LIKE 'J60%' OR d.icd_code LIKE 'J61%' OR d.icd_code LIKE 'J62%' OR d.icd_code LIKE 'J63%' OR d.icd_code LIKE 'J64%' OR d.icd_code LIKE 'J65%' OR d.icd_code LIKE 'J66%' OR d.icd_code LIKE 'J67%' OR d.icd_code = 'J703' OR d.icd_code = 'J841' OR d.icd_code = 'J961'))
         THEN 1 ELSE 0 END) AS copd_flag,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('4402','4403','4404','4431','4432','4433','4434','4435','4436','4437','4438','4439','4471','5571','5579','V434'))
              OR (d.icd_version = 10 AND d.icd_code IN ('I702','I703','I704','I705','I706','I707','I708','I709','I738','I739','I771','I790','I792','K551','K558','K559','Z959'))
         THEN 1 ELSE 0 END) AS pvd_flag,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '571%' OR d.icd_code IN ('5722','5723','5724','5728','V427')))
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'I85%' OR d.icd_code = 'I864' OR d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K713' OR d.icd_code LIKE 'K714' OR d.icd_code LIKE 'K715' OR d.icd_code LIKE 'K717' OR d.icd_code LIKE 'K719' OR d.icd_code LIKE 'K73%' OR d.icd_code LIKE 'K74%' OR d.icd_code LIKE 'K76%' OR d.icd_code = 'Z944'))
         THEN 1 ELSE 0 END) AS liver_flag,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '280%' OR d.icd_code LIKE '281%' OR d.icd_code IN ('2824','2825','2826','2831','2841','2842','2851','28521','28522','2853','2859','V1341','V1342')))
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'D50%' OR d.icd_code LIKE 'D51%' OR d.icd_code LIKE 'D52%' OR d.icd_code LIKE 'D53%' OR d.icd_code LIKE 'D54%' OR d.icd_code LIKE 'D55%' OR d.icd_code LIKE 'D56%' OR d.icd_code LIKE 'D57%' OR d.icd_code LIKE 'D58%' OR d.icd_code LIKE 'D59%' OR d.icd_code LIKE 'D60%' OR d.icd_code LIKE 'D61%' OR d.icd_code LIKE 'D62%' OR d.icd_code LIKE 'D63%' OR d.icd_code LIKE 'D64%' OR d.icd_code LIKE 'D65%' OR d.icd_code LIKE 'D66%' OR d.icd_code LIKE 'D67%' OR d.icd_code LIKE 'D68%' OR d.icd_code LIKE 'D69%' OR d.icd_code LIKE 'D70%' OR d.icd_code LIKE 'D71%' OR d.icd_code LIKE 'D72%' OR d.icd_code LIKE 'D73%' OR d.icd_code LIKE 'D74%' OR d.icd_code LIKE 'D75%' OR d.icd_code = 'Z8501' OR d.icd_code = 'Z905'))
         THEN 1 ELSE 0 END) AS anemia_flag,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code = '2780')
              OR (d.icd_version = 10 AND d.icd_code LIKE 'E66%')
         THEN 1 ELSE 0 END) AS obesity_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
),
combined AS (
  SELECT 
    c.hadm_id,
    c.hospital_expire_flag,
    c.los,
    cf.diabetes_flag,
    cf.ckd_flag,
    (1 +  -- HF is always present (cohort-defining)
      cf.diabetes_flag + cf.ckd_flag + cf.hypertension_flag + 
      cf.afib_flag + cf.copd_flag + cf.pvd_flag + 
      cf.liver_flag + cf.anemia_flag + cf.obesity_flag
    ) AS comorbidity_count
  FROM cohort c
  INNER JOIN condition_flags cf
    ON c.hadm_id = cf.hadm_id
),
with_tertile AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS comorbidity_tertile
  FROM combined
),
with_groups AS (
  SELECT 
    hadm_id,
    hospital_expire_flag,
    CASE WHEN los <= 5 THEN '≤5' ELSE '>5' END AS los_group,
    comorbidity_tertile,
    ckd_flag,
    diabetes_flag
  FROM with_tertile
)
SELECT 
  los_group,
  CASE comorbidity_tertile
    WHEN 1 THEN 'Low'
    WHEN 2 THEN 'Med'
    WHEN 3 THEN 'High'
  END AS comorbidity_tertile,
  COUNT(*) AS N,
  ROUND(AVG(hospital_expire_flag) * 100, 1) AS mortality_pct,
  ROUND(AVG(ckd_flag) * 100, 1) AS ckd_prevalence_pct,
  ROUND(AVG(diabetes_flag) * 100, 1) AS diabetes_prevalence_pct
FROM with_groups
GROUP BY los_group, comorbidity_tertile
ORDER BY 
  CASE los_group WHEN '≤5' THEN 1 ELSE 2 END,
  comorbidity_tertile;