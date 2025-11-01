WITH filtered_admissions AS (
  SELECT 
    a.*,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.services` s 
      WHERE s.subject_id = a.subject_id 
        AND s.hadm_id = a.hadm_id 
        AND s.curr_service LIKE 'MEDICINE%'
    )
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
    WHEN discharge_location = 'HOME' THEN 'Discharge home'
    ELSE 'Other'
  END AS discharge_category,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  SUM(CASE WHEN los_days <= 5 THEN 1.0 ELSE 0 END) / COUNT(*) AS proportion_los_le_5
FROM filtered_admissions
GROUP BY discharge_category
HAVING discharge_category != 'Other'
ORDER BY discharge_category;