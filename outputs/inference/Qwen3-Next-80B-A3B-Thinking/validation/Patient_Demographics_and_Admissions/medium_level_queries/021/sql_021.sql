WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND s.curr_service = 'SURG'
    )
    AND (
      a.hospital_expire_flag = 1
      OR a.discharge_location IN (
        'Home', 
        'Home with Home Health Care', 
        'Rehab Facility', 
        'Skilled Nursing Facility', 
        'Hospice'
      )
    )
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-hospital Mortality'
    WHEN discharge_location IN ('Home', 'Home with Home Health Care') THEN 'Discharged Home'
    WHEN discharge_location IN ('Rehab Facility', 'Skilled Nursing Facility', 'Hospice') THEN 'Discharged to Facility'
  END AS discharge_category,
  AVG(los) AS mean_los,
  STDDEV(los) AS std_los,
  AVG(CASE WHEN los <= 7 THEN 1.0 ELSE 0 END) * 100 AS percent_los_le_7
FROM filtered_admissions
GROUP BY discharge_category;