SELECT
  discharge_category,
  COUNTIF(los >= 7) / COUNT(*) AS prop_los_ge7,
  COUNTIF(los >= 14) / COUNT(*) AS prop_los_ge14,
  PERCENTILE_CONT(los, 0.07) AS los_7th_percentile
FROM (
  SELECT
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 'home'
      WHEN a.discharge_location = 'HOSPICE' THEN 'hospice'
      WHEN a.discharge_location IN ('DEATH', 'EXPIRED') THEN 'in-hospital death'
      ELSE NULL
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND s.curr_service IN ('MED', 'MEDICINE')
    )
) subquery
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category;