WITH stay_hr AS (
  SELECT 
    icu.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id 
    AND icu.stay_id = ce.stay_id
    AND ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime 
    AND ce.charttime <= icu.outtime
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 62 AND 72
  GROUP BY 
    icu.stay_id
  HAVING 
    COUNT(ce.valuenum) > 0
),
stay_mi AS (
  SELECT DISTINCT
    icu.stay_id,
    1 AS has_acute_mi
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.subject_id = diag.subject_id 
    AND icu.hadm_id = diag.hadm_id
  INNER JOIN 
    stay_hr shr
    ON icu.stay_id = shr.stay_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 62 AND 72
    AND diag.icd_version = 10
    AND diag.icd_code LIKE 'I21%'
    AND diag.seq_num <= 5
),
combined_stays AS (
  SELECT 
    shr.stay_id,
    shr.mean_hr,
    COALESCE(smi.has_acute_mi, 0) AS has_acute_mi
  FROM 
    stay_hr shr
  LEFT JOIN 
    stay_mi smi
    ON shr.stay_id = smi.stay_id
)
SELECT 
  CASE 
    WHEN mean_hr < 60 THEN '<60'
    WHEN mean_hr >= 60 AND mean_hr <= 99 THEN '60–99'
    WHEN mean_hr >= 100 AND mean_hr <= 119 THEN '100–119'
    WHEN mean_hr >= 120 THEN '≥120'
  END AS hr_category,
  COUNT(*) AS stay_count,
  ROUND(SUM(has_acute_mi) * 100.0 / COUNT(*), 2) AS pct_with_acute_mi
FROM 
  combined_stays
WHERE 
  mean_hr IS NOT NULL
GROUP BY 
  hr_category
ORDER BY 
  MIN(mean_hr);