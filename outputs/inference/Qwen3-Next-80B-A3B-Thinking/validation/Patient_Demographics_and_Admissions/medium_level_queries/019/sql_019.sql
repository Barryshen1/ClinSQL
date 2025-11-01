SELECT
  CASE
    WHEN discharge_location = 'Home' THEN 'Home'
    WHEN discharge_location = 'Hospice' THEN 'Hospice'
    WHEN discharge_location IN ('Death', 'Expired') THEN 'Death'
    ELSE NULL
  END AS discharge_category,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS stddev_los
FROM (
  SELECT
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    DATE_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND DATE_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 63 AND 73
    AND a.admission_location = 'Transfer from another hospital'
) subquery
GROUP BY discharge_category
HAVING discharge_category IS NOT NULL;