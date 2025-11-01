WITH 
ami_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 46 AND 56 AND dicd.long_title LIKE '%Myocardial infarction%'
),

major_complications AS (
  SELECT DISTINCT hadm_id, COUNT(*) as count_complications
  FROM (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE icd_code IN ('41001', '41011', '41021', '41031', '41041', '41051', '41061', '41071', '41081', '41091')  
    UNION ALL
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` WHERE icd_code IN ('3615', '3616', '3617')  
  ) t
  GROUP BY hadm_id
),

composite_risk AS (
  SELECT ap.subject_id, ap.hadm_id, ap.anchor_age, COALESCE(mc.count_complications, 0) as count_complications,
         ap.anchor_age + COALESCE(mc.count_complications, 0) as composite_score,
         CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END as in_hospital_mortality,
         COALESCE(mc.count_complications, 0) > 0 as major_complication_flag,
         icu.los
  FROM ami_patients ap
  LEFT JOIN major_complications mc ON ap.hadm_id = mc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ap.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ap.hadm_id = icu.hadm_id
),

quintiles AS (
  SELECT composite_score, 
         NTILE(5) OVER (ORDER BY composite_score) as quintile,
         in_hospital_mortality,
         major_complication_flag,
         los
  FROM composite_risk
)

SELECT 
  quintile,
  AVG(CAST(in_hospital_mortality AS INT64)) * 100 as in_hospital_mortality_pct,
  AVG(CAST(major_complication_flag AS INT64)) * 100 as major_complication_pct,
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] as median_survivor_los  
FROM quintiles
GROUP BY quintile
ORDER BY quintile;