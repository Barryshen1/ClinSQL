WITH surgical_admissions AS (
  SELECT 
    a.hadm_id,
    a.discharge_location,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND s.curr_service = 'SURG'
    )
)
SELECT
  discharge_category,
  COUNTIF(los >= 7) / COUNT(*) AS prop_los_ge7,
  COUNTIF(los >= 14) / COUNT(*) AS prop_los_ge14
FROM (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN discharge_location IN ('Home', 'Home with Home Care', 'Home with Hospice') THEN 'Home'
      WHEN discharge_location IN ('SNF', 'Rehabilitation', 'LTACH', 'Other Facility', 'Other') THEN 'Facility'
      ELSE NULL
    END AS discharge_category,
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM surgical_admissions
)
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category;