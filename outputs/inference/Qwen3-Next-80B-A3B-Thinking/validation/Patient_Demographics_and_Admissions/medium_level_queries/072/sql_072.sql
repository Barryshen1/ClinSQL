SELECT
  CASE
    WHEN a.hospital_expire_flag = 1 THEN 'DEATH'
    WHEN a.discharge_location = 'HOSPICE' THEN 'HOSPICE'
    WHEN a.discharge_location = 'HOME' THEN 'HOME'
    ELSE NULL
  END AS discharge_category,
  AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los,
  APPROX_QUANTILES(DATE_DIFF(a.dischtime, a.admittime, DAY), 100)[OFFSET(50)] AS median_los,
  SUM(CASE WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN 1 ELSE 0 END) / COUNT(*) AS prop_los_le_5
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
WHERE
  p.gender = 'M'
  AND DATE_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 74 AND 84
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.services` s
    WHERE s.hadm_id = a.hadm_id
      AND s.curr_service = 'MED'
  )
GROUP BY discharge_category;