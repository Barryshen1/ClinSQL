SELECT
  discharge_category,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] - APPROX_QUANTILES(los, 100)[OFFSET(25)] AS iqr_los
FROM (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'DEATH'
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
    END AS discharge_category,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'EMERGENCY'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
    AND (a.hospital_expire_flag = 1 OR a.discharge_location IN ('HOME', 'HOSPICE'))
) subquery
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category;