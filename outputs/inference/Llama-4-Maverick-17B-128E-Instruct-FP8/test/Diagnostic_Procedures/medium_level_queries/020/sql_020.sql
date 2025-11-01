WITH 
-- Filter patients by age and gender
filtered_patients AS (
  SELECT subject_id, anchor_age, anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 72 AND 82
),

-- Calculate admission details and LOS
admission_details AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN filtered_patients p ON a.subject_id = p.subject_id
  WHERE DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Count diagnostic imaging procedures
imaging_procedures AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS num_imaging
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%imaging%' OR LOWER(d.long_description) LIKE '%imaging%'
  GROUP BY h.hadm_id
)

-- Main query to calculate admission counts and mean diagnostic imaging procedures
SELECT 
  CASE 
    WHEN ad.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ad.los BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_category,
  ad.icu_use,
  COUNT(ad.hadm_id) AS admission_count,
  AVG(COALESCE(ip.num_imaging, 0)) AS mean_imaging_procedures
FROM admission_details ad
LEFT JOIN imaging_procedures ip ON ad.hadm_id = ip.hadm_id
WHERE ad.los BETWEEN 1 AND 7
GROUP BY los_category, ad.icu_use
ORDER BY los_category, ad.icu_use;