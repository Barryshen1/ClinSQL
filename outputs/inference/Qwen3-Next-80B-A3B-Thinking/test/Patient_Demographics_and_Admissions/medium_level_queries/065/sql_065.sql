SELECT
  category,
  AVG(los) AS mean_los,
  STDDEV(los) AS sd_los
FROM (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
      WHEN a.discharge_location = 'Home' THEN 'Discharged Home'
      WHEN a.discharge_location = 'Hospice' THEN 'Discharged to Hospice'
    END AS category,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    )
    AND (a.hospital_expire_flag = 1 OR a.discharge_location IN ('Home', 'Hospice'))
) subquery
GROUP BY category;