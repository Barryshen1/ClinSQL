WITH cohort AS (
  SELECT 
    p.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'E11%' 
        AND d.icd_version = 10
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'I50%' 
        AND d.icd_version = 10
    )
),

insulin_prescriptions AS (
  SELECT 
    p.subject_id,
    p.starttime,
    CASE 
      WHEN p.drug LIKE '%Glargine%' OR p.drug LIKE '%Detemir%' OR p.drug LIKE '%NPH%' THEN 'basal'
      WHEN p.drug LIKE '%Regular%' 
        AND (poe.order_type LIKE '%sliding scale%' OR poe.order_subtype LIKE '%sliding scale%') THEN 'sliding-scale'
      WHEN p.drug LIKE '%Regular%' THEN 'bolus'
      ELSE NULL
    END AS insulin_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.poe` poe 
    ON p.poe_id = poe.poe_id
  WHERE p.drug LIKE '%Insulin%'
    AND p.starttime IS NOT NULL
),

first_48h AS (
  SELECT 
    c.subject_id,
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'basal' THEN 1 ELSE 0 END), 0) AS has_basal_48h,
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'bolus' THEN 1 ELSE 0 END), 0) AS has_bolus_48h,
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'sliding-scale' THEN 1 ELSE 0 END), 0) AS has_sliding_48h,
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'basal' THEN 1 ELSE 0 END), 0) * 
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'bolus' THEN 1 ELSE 0 END), 0) AS has_basal_bolus_48h
  FROM cohort c
  LEFT JOIN insulin_prescriptions ip 
    ON c.subject_id = ip.subject_id
    AND ip.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '48' HOUR
  GROUP BY c.subject_id
),

final_12h AS (
  SELECT 
    c.subject_id,
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'basal' THEN 1 ELSE 0 END), 0) AS has_basal_12h,
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'bolus' THEN 1 ELSE 0 END), 0) AS has_bolus_12h,
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'sliding-scale' THEN 1 ELSE 0 END), 0) AS has_sliding_12h,
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'basal' THEN 1 ELSE 0 END), 0) * 
    COALESCE(MAX(CASE WHEN ip.insulin_type = 'bolus' THEN 1 ELSE 0 END), 0) AS has_basal_bolus_12h
  FROM cohort c
  LEFT JOIN insulin_prescriptions ip 
    ON c.subject_id = ip.subject_id
    AND ip.starttime BETWEEN c.dischtime - INTERVAL '12' HOUR AND c.dischtime
  GROUP BY c.subject_id
)

SELECT 
  'basal' AS insulin_type,
  AVG(has_basal_48h) * 100 AS first_48h_pct,
  AVG(has_basal_12h) * 100 AS final_12h_pct,
  (AVG(has_basal_12h) - AVG(has_basal_48h)) * 100 AS net_change
FROM first_48h f
JOIN final_12h s ON f.subject_id = s.subject_id

UNION ALL

SELECT 
  'bolus',
  AVG(has_bolus_48h) * 100,
  AVG(has_bolus_12h) * 100,
  (AVG(has_bolus_12h) - AVG(has_bolus_48h)) * 100
FROM first_48h f
JOIN final_12h s ON f.subject_id = s.subject_id

UNION ALL

SELECT 
  'sliding-scale',
  AVG(has_sliding_48h) * 100,
  AVG(has_sliding_12h) * 100,
  (AVG(has_sliding_12h) - AVG(has_sliding_48h)) * 100
FROM first_48h f
JOIN final_12h s ON f.subject_id = s.subject_id

UNION ALL

SELECT 
  'basal-bolus',
  AVG(has_basal_bolus_48h) * 100,
  AVG(has_basal_bolus_12h) * 100,
  (AVG(has_basal_bolus_12h) - AVG(has_basal_bolus_48h)) * 100
FROM first_48h f
JOIN final_12h s ON f.subject_id = s.subject_id;