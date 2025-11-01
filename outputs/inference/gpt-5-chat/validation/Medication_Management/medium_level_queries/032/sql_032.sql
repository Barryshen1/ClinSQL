WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
dx AS (
  SELECT hadm_id,
         MAX(CASE 
             WHEN (di.icd_version = 9 AND di.icd_code LIKE '250%')
               OR (di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%' OR di.icd_code LIKE 'E14%'))
             THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE 
             WHEN (di.icd_version = 9 AND di.icd_code IN ('42821','42823','42831','42833'))
               OR (di.icd_version = 10 AND di.icd_code IN ('I5021','I5023','I5031','I5033'))
             THEN 1 ELSE 0 END) AS has_acute_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY hadm_id
),
cohort_final AS (
  SELECT c.*
  FROM cohort c
  JOIN dx
    ON c.hadm_id = dx.hadm_id
  WHERE dx.has_diabetes = 1
    AND dx.has_acute_hf = 1
),
emar_with_detail AS (
  SELECT e.hadm_id, e.charttime, LOWER(ed.product_description) AS product_desc
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.subject_id = ed.subject_id 
   AND e.emar_id = ed.emar_id
   AND e.emar_seq = ed.emar_seq
),
med_flags AS (
  SELECT cf.hadm_id,
    CASE WHEN SUM(CASE WHEN product_desc LIKE '%glargine%' 
                           OR product_desc LIKE '%detemir%' 
                           OR product_desc LIKE '%nph%' 
                       THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS basal_flag,
    CASE WHEN SUM(CASE WHEN product_desc LIKE '%lispro%' 
                           OR product_desc LIKE '%aspart%' 
                           OR product_desc LIKE '%regular insulin%' 
                       THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS bolus_flag,
    CASE WHEN SUM(CASE WHEN product_desc LIKE '%sliding scale%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS sliding_flag
  FROM cohort_final cf
  JOIN emar_with_detail ewd
    ON cf.hadm_id = ewd.hadm_id
  WHERE ewd.charttime BETWEEN cf.admittime AND cf.admittime + INTERVAL 24 HOUR
  GROUP BY cf.hadm_id
),
med_flags_final12h AS (
  SELECT cf.hadm_id,
    CASE WHEN SUM(CASE WHEN product_desc LIKE '%glargine%' 
                           OR product_desc LIKE '%detemir%' 
                           OR product_desc LIKE '%nph%' 
                       THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS basal_flag,
    CASE WHEN SUM(CASE WHEN product_desc LIKE '%lispro%' 
                           OR product_desc LIKE '%aspart%' 
                           OR product_desc LIKE '%regular insulin%' 
                       THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS bolus_flag,
    CASE WHEN SUM(CASE WHEN product_desc LIKE '%sliding scale%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS sliding_flag
  FROM cohort_final cf
  JOIN emar_with_detail ewd
    ON cf.hadm_id = ewd.hadm_id
  WHERE ewd.charttime BETWEEN cf.dischtime - INTERVAL 12 HOUR AND cf.dischtime
  GROUP BY cf.hadm_id
),
stats AS (
  SELECT
    COUNT(*) AS total_adm,
    SUM(CASE WHEN basal_flag=1 AND bolus_flag=1 THEN 1 ELSE 0 END) AS basal_bolus_first24,
    SUM(CASE WHEN basal_flag=1 AND bolus_flag=0 AND sliding_flag=0 THEN 1 ELSE 0 END) AS basal_only_first24,
    SUM(CASE WHEN basal_flag=0 AND bolus_flag=1 AND sliding_flag=0 THEN 1 ELSE 0 END) AS bolus_only_first24,
    SUM(CASE WHEN sliding_flag=1 THEN 1 ELSE 0 END) AS sliding_first24
  FROM med_flags
),
stats_final AS (
  SELECT
    COUNT(*) AS total_adm,
    SUM(CASE WHEN basal_flag=1 AND bolus_flag=1 THEN 1 ELSE 0 END) AS basal_bolus_final12,
    SUM(CASE WHEN basal_flag=1 AND bolus_flag=0 AND sliding_flag=0 THEN 1 ELSE 0 END) AS basal_only_final12,
    SUM(CASE WHEN basal_flag=0 AND bolus_flag=1 AND sliding_flag=0 THEN 1 ELSE 0 END) AS bolus_only_final12,
    SUM(CASE WHEN sliding_flag=1 THEN 1 ELSE 0 END) AS sliding_final12
  FROM med_flags_final12h
)
SELECT 
  'Basal-Bolus' AS regimen,
  ROUND( (s.basal_bolus_first24 / s.total_adm) * 100, 2) AS pct_first_24h,
  ROUND( (sf.basal_bolus_final12 / sf.total_adm) * 100, 2) AS pct_final_12h,
  ROUND( ((sf.basal_bolus_final12 / sf.total_adm) - (s.basal_bolus_first24 / s.total_adm)) * 100, 2) AS pct_point_change
FROM stats s
CROSS JOIN stats_final sf
UNION ALL
SELECT 
  'Basal only', 
  ROUND( (s.basal_only_first24 / s.total_adm) * 100, 2),
  ROUND( (sf.basal_only_final12 / sf.total_adm) * 100, 2),
  ROUND( ((sf.basal_only_final12 / sf.total_adm) - (s.basal_only_first24 / s.total_adm)) * 100, 2)
FROM stats s
CROSS JOIN stats_final sf
UNION ALL
SELECT 
  'Bolus only',
  ROUND( (s.bolus_only_first24 / s.total_adm) * 100, 2),
  ROUND( (sf.bolus_only_final12 / sf.total_adm) * 100, 2),
  ROUND( ((sf.bolus_only_final12 / sf.total_adm) - (s.bolus_only_first24 / s.total_adm)) * 100, 2)
FROM stats s
CROSS JOIN stats_final sf
UNION ALL
SELECT 
  'Sliding scale',
  ROUND( (s.sliding_first24 / s.total_adm) * 100, 2),
  ROUND( (sf.sliding_final12 / sf.total_adm) * 100, 2),
  ROUND( ((sf.sliding_final12 / sf.total_adm) - (s.sliding_first24 / s.total_adm)) * 100, 2)
FROM stats s
CROSS JOIN stats_final sf;