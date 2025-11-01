WITH base AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
),
services_initial AS (
  SELECT 
    subject_id,
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
filtered AS (
  SELECT 
    b.*
  FROM base b
  INNER JOIN services_initial s
    ON b.subject_id = s.subject_id AND b.hadm_id = s.hadm_id
  WHERE 
    s.rn = 1
    AND s.curr_service = 'MED'
    AND b.gender = 'M'
    AND b.age_at_admission BETWEEN 74 AND 84
),
categorized AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOME WITH HOME HEALTH') THEN 'Discharge home'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      ELSE NULL 
    END AS discharge_category
  FROM filtered
)
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los,
  COUNTIF(los_days <= 5) / COUNT(*) AS prop_los_le_5
FROM categorized
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY discharge_category;