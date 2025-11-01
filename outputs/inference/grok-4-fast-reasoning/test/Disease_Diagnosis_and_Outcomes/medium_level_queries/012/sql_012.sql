WITH patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
),
adms AS (
  SELECT a.*, p.anchor_age,
         (EXTRACT(YEAR FROM a.admittime) - 2008 + p.anchor_age) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients p ON a.subject_id = p.subject_id
  WHERE (EXTRACT(YEAR FROM a.admittime) - 2008 + p.anchor_age) BETWEEN 83 AND 93
),
hf_adms AS (
  SELECT DISTINCT ad.hadm_id, ad.subject_id, ad.admittime, ad.dischtime, ad.hospital_expire_flag, ad.age_at_adm,
         DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
  FROM adms ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d ON ad.hadm_id = d.hadm_id
  WHERE ((d.icd_version = 9 AND d.icd_code LIKE '428%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%'))
     AND ad.dischtime > ad.admittime
),
comorb AS (
  SELECT hadm_id,
         MAX(CASE WHEN ((icd_version = 9 AND icd_code LIKE '250%') OR (icd_version = 10 AND icd_code LIKE 'E1[0-4]%')) THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE WHEN ((icd_version = 9 AND icd_code LIKE '585%') OR (icd_version = 10 AND icd_code LIKE 'N18%')) THEN 1 ELSE 0 END) AS has_ckd,
         MAX(CASE WHEN ((icd_version = 9 AND icd_code LIKE '40[0-9]%') OR (icd_version = 10 AND icd_code LIKE 'I1[0-5]%')) THEN 1 ELSE 0 END) AS has_htn,
         MAX(CASE WHEN ((icd_version = 9 AND icd_code LIKE '41[0-4]%') OR (icd_version = 10 AND (icd_code LIKE 'I20%' OR icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I23%' OR icd_code LIKE 'I24%' OR icd_code LIKE 'I25%'))) THEN 1 ELSE 0 END) AS has_ihd,
         MAX(CASE WHEN ((icd_version = 9 AND icd_code = '427.31') OR (icd_version = 10 AND icd_code = 'I48')) THEN 1 ELSE 0 END) AS has_afib,
         MAX(CASE WHEN ((icd_version = 9 AND icd_code LIKE '49[0-6]%') OR (icd_version = 10 AND (icd_code LIKE 'J4[0-4]%' OR icd_code = 'J47'))) THEN 1 ELSE 0 END) AS has_copd
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE hadm_id IN (SELECT hadm_id FROM hf_adms)
  GROUP BY hadm_id
),
base AS (
  SELECT h.hadm_id, h.hospital_expire_flag, h.los_days,
         COALESCE(c.has_diabetes, 0) AS diabetes_flag,
         COALESCE(c.has_ckd, 0) AS ckd_flag,
         CASE WHEN (COALESCE(c.has_diabetes, 0) + COALESCE(c.has_ckd, 0) + COALESCE(c.has_htn, 0) + COALESCE(c.has_ihd, 0) + COALESCE(c.has_afib, 0) + COALESCE(c.has_copd, 0)) <= 1 THEN '0-1'
              WHEN (COALESCE(c.has_diabetes, 0) + COALESCE(c.has_ckd, 0) + COALESCE(c.has_htn, 0) + COALESCE(c.has_ihd, 0) + COALESCE(c.has_afib, 0) + COALESCE(c.has_copd, 0)) = 2 THEN '2'
              ELSE '>=3'
         END AS comorbidity_burden,
         CASE WHEN EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu`.icustays i WHERE i.hadm_id = h.hadm_id) THEN 'ICU' ELSE 'non-ICU' END AS icu_flag,
         CASE WHEN h.los_days < 8 THEN '<8' ELSE '>=8' END AS los_cat
  FROM hf_adms h
  LEFT JOIN comorb c ON h.hadm_id = c.hadm_id
  WHERE h.los_days >= 0
),
temp AS (
  SELECT *,
         PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY icu_flag, los_cat, comorbidity_burden) AS median_los
  FROM base
)
SELECT 
  icu_flag,
  los_cat,
  comorbidity_burden,
  COUNT(*) AS n,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ANY_VALUE(median_los) AS median_los,
  ROUND(AVG(diabetes_flag) * 100, 2) AS diabetes_prevalence_pct,
  ROUND(AVG(ckd_flag) * 100, 2) AS ckd_prevalence_pct
FROM temp
GROUP BY icu_flag, los_cat, comorbidity_burden
ORDER BY icu_flag, los_cat, comorbidity_burden;