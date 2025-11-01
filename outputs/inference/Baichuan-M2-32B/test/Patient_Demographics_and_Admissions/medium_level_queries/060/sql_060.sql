SELECT
  discharge_outcome,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS std_los,
  (SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*)) * 100 AS percent_le_10_days
FROM (
  SELECT
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location LIKE '%Hospice%' THEN 'Hospice'
      WHEN a.discharge_location LIKE '%Home%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_type = 'Emergency'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
WHERE
  discharge_outcome IN ('In-hospital death', 'Hospice', 'Home')
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;