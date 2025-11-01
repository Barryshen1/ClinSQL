WITH first_troponin AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    l.charttime,
    l.valuenum,
    CASE 
      WHEN l.valuenum < 14 THEN 'Normal'
      WHEN l.valuenum <= 46 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
    ON l.itemid = dli.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND a.admission_type = 'EMERGENCY'
    AND LOWER(dli.label) LIKE '%troponin t%'
    AND l.valuenum > 0
    AND l.charttime >= a.admittime  -- Ensure measurement during admission
),
ranked_troponin AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM first_troponin
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  SUM(hospital_expire_flag) AS mortality_count,
  COUNT(*) AS total_in_category,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage
FROM ranked_troponin
WHERE rn = 1
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;