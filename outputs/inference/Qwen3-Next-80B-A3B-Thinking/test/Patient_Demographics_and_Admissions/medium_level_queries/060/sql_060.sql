SELECT
  CASE
    WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN a.discharge_location = 'Home' THEN 'Home'
    WHEN a.discharge_location = 'Hospice' THEN 'Hospice'
  END AS discharge_outcome,
  AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los,
  STDDEV(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS sd_los,
  (COUNTIF(DATE_DIFF(a.dischtime, a.admittime, DAY) <= 10) * 100.0 / COUNT(*)) AS percent_le_10
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND a.admission_location = 'Emergency Room'
  AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 50 AND 60
  AND (
    a.hospital_expire_flag = 1
    OR a.discharge_location IN ('Home', 'Hospice')
  )
GROUP BY
  discharge_outcome;