WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 46 AND 56
),
hs_tnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS hs_tnt_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE 
    d.label LIKE '%hs-TnT%'  
),
categorized_hs_tnt AS (
  SELECT 
    hadm_id,
    hs_tnt_value,
    CASE
      WHEN hs_tnt_value < 14 THEN 'Normal'  
      WHEN hs_tnt_value BETWEEN 14 AND 52 THEN 'Borderline'  
      ELSE 'Myocardial Injury'
    END AS hs_tnt_category
  FROM 
    hs_tnt
  WHERE 
    rn = 1  
),
acs_admissions AS (
  SELECT 
    d.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    dicd.long_title LIKE '%Acute coronary syndrome%'  
)
SELECT 
  cht.hs_tnt_category,
  COUNT(DISTINCT pi.hadm_id) AS count,
  COUNT(DISTINCT pi.hadm_id) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM categorized_hs_tnt JOIN acs_admissions USING (hadm_id)) AS percentage,
  AVG(pi.los_days) AS mean_los_days
FROM 
  patient_info pi
JOIN 
  categorized_hs_tnt cht ON pi.hadm_id = cht.hadm_id
JOIN 
  acs_admissions aa ON pi.hadm_id = aa.hadm_id
GROUP BY 
  cht.hs_tnt_category
ORDER BY 
  cht.hs_tnt_category;