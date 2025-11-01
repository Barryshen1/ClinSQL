WITH first_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 46 AND 56
    AND adm.hospital_expire_flag = 0  -- Exclude expired for LOS
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) = 1
),
first_hstnt AS (
  SELECT 
    fa.*,
    le.charttime,
    le.valuenum,
    CASE 
      WHEN le.valuenum < 14 THEN 'Normal'
      WHEN le.valuenum >= 14 AND le.valuenum <= 46 THEN 'Borderline'
      WHEN le.valuenum > 46 THEN 'Myocardial Injury'
      ELSE 'Other'
    END AS hstnt_category,
    DATE_DIFF(DATE(fa.dischtime), DATE(fa.admittime), DAY) AS los_days
  FROM 
    first_admissions fa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON fa.hadm_id = le.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
  ON le.itemid = dli.itemid
  WHERE 
    le.valuenum IS NOT NULL
    AND dli.label LIKE '%High Sensitivity Troponin%'
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY fa.hadm_id ORDER BY le.charttime) = 1  -- First hs-TnT per admission
)
SELECT 
  hstnt_category,
  COUNT(*) AS count_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM 
  first_hstnt
WHERE 
  hstnt_category != 'Other'  -- Exclude uncategorized
GROUP BY 
  hstnt_category
ORDER BY 
  CASE hstnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;