SELECT
  CASE
    WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
    WHEN a.discharge_location LIKE '%HOME%' THEN 'Home'
    ELSE 'Other'
  END AS discharge_outcome,
  COUNT(*) AS n,
  AVG(i.los) AS mean_los,
  APPROX_QUANTILES(i.los, 2)[OFFSET(1)] AS median_los,
  ROUND(SUM(CASE WHEN i.los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS percent_los_le_10_days
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN
  physionet-data.mimiciv_3_1_icu.icustays i
  ON a.hadm_id = i.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 63 AND 73
  AND i.los IS NOT NULL
GROUP BY
  discharge_outcome
HAVING
  discharge_outcome IN ('Home', 'Hospice', 'In-hospital death')
ORDER BY
  discharge_outcome;