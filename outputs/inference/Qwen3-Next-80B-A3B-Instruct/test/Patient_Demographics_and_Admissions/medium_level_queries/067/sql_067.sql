WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN a.discharge_location = 'Death' THEN 'In-hospital death'
      ELSE a.discharge_location
    END AS discharge_location,
    p.gender,
    p.anchor_age,
    CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS FLOAT) / 24 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.dischtime IS NOT NULL
    AND a.hadm_id IN (
      SELECT DISTINCT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.services` 
      WHERE curr_service = 'MED'
    )
    AND a.discharge_location IN ('Home', 'Hospice', 'Death')
)
SELECT
  AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0 END) AS prop_los_ge_7,
  AVG(CASE WHEN los_days >= 14 THEN 1.0 ELSE 0 END) AS prop_los_ge_14,
  PERCENTILE_CONT(CASE WHEN discharge_location = 'Home' THEN los_days ELSE NULL END, 0.07) AS p7_home,
  PERCENTILE_CONT(CASE WHEN discharge_location = 'Hospice' THEN los_days ELSE NULL END, 0.07) AS p7_hospice,
  PERCENTILE_CONT(CASE WHEN discharge_location = 'In-hospital death' THEN los_days ELSE NULL END, 0.07) AS p7_in_hospital_death
FROM 
  filtered_admissions;