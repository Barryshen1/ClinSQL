WITH filtered_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.dod,
    a.hadm_id,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    i.stay_id,
    i.los
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a 
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND i.los IS NOT NULL
),
death_categories AS (
  SELECT 
    stay_id,
    los,
    CASE 
      WHEN deathtime IS NOT NULL THEN 'In-hospital'
      WHEN dod IS NOT NULL AND dod > dischtime AND discharge_location = 'Home' THEN 'Home'
      WHEN dod IS NOT NULL AND dod > dischtime AND discharge_location IN ('Skilled Nursing Facility', 'Rehabilitation', 'Long Term Care Hospital', 'Hospice') THEN 'Facility'
      ELSE NULL
    END AS death_category
  FROM filtered_patients
)
SELECT 
  death_category,
  COUNT(*) AS n,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(STDDEV(los), 2) AS sd_los,
  ROUND(100.0 * SUM(CASE WHEN los < 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_los_lt_10
FROM death_categories
WHERE death_category IS NOT NULL
GROUP BY death_category
ORDER BY death_category;