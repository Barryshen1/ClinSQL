WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag,
    a.discharge_location,
    s.curr_service,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location = 'Hospice' THEN 'Hospice'
      WHEN a.discharge_location = 'Disch home' THEN 'Home'
      ELSE NULL 
    END AS discharge_cat
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.services` s
    ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND s.prev_service IS NULL
    AND s.curr_service = 'MEDICINE'
    AND a.dischtime > a.admittime
    AND a.hadm_id IS NOT NULL
)
SELECT 
  discharge_cat,
  COUNT(*) AS total_n,
  SAFE_DIVIDE(COUNTIF(los >= 7), COUNT(*)) AS prop_los_ge7,
  SAFE_DIVIDE(COUNTIF(los >= 14), COUNT(*)) AS prop_los_ge14,
  SAFE_DIVIDE(COUNTIF(los <= 7), COUNT(*)) AS perc_los_le7
FROM cohort
WHERE discharge_cat IS NOT NULL
GROUP BY discharge_cat
ORDER BY 
  CASE discharge_cat
    WHEN 'Home' THEN 1
    WHEN 'Hospice' THEN 2
    WHEN 'In-hospital death' THEN 3
  END;