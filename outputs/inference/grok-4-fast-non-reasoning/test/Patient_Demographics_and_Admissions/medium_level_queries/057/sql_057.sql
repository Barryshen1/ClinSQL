WITH filtered_stays AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.los,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),
categorized_outcomes AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'REHAB/DISTINCT PART', 'SNF', 'LONG TERM CARE HOSPITAL') THEN 'Home'
      WHEN discharge_location IN ('HOSPICE', 'HOSPICE/TRANSFERRED') THEN 'Hospice'
      ELSE NULL  -- Exclude uncategorized
    END AS outcome_category
  FROM 
    filtered_stays
  WHERE 
    outcome_category IS NOT NULL
)
SELECT 
  outcome_category,
  APPROX_QUANTILES(los, 5)[OFFSET(2)] AS p50_los,
  APPROX_QUANTILES(los, 5)[OFFSET(3)] AS p75_los,
  APPROX_QUANTILES(los, 10)[OFFSET(9)] AS p90_los,
  APPROX_QUANTILES(los, 20)[OFFSET(19)] AS p95_los,
  ROUND(AVG(CASE WHEN los <= 7 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_los_le_7d
FROM 
  categorized_outcomes
GROUP BY 
  outcome_category
ORDER BY 
  outcome_category;