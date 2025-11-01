WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.los,
    a.discharge_location,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.admission_type != 'OBSERVATION'
    AND a.hospital_expire_flag IN (0, 1)  -- Ensure flag is set
    AND a.discharge_location IS NOT NULL  -- Exclude unknown
),
discharge_category AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE 'HOME%' OR UPPER(discharge_location) LIKE 'DISCH%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_group
  FROM 
    cohort
)
SELECT 
  discharge_group,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)], 2) AS median_los_days,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(90)], 2) AS p90_los_days,
  COUNT(*) AS n_stays
FROM 
  discharge_category
GROUP BY 
  discharge_group
ORDER BY 
  discharge_group;