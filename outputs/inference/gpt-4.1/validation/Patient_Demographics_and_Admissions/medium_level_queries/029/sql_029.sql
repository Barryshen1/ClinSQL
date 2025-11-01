SELECT
  CASE
    WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN a.hospital_expire_flag = 0 THEN 'Discharged alive'
    ELSE 'Unknown'
  END AS survival_status,
  COUNT(*) AS n_stays,
  ROUND(AVG(i.los), 2) AS mean_los,
  ROUND(STDDEV(i.los), 2) AS sd_los,
  ROUND(100 * SUM(CASE WHEN i.los < 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_lt_7
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` i
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON i.hadm_id = a.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON i.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 35 AND 45
  AND i.los IS NOT NULL
  AND i.los > 0
GROUP BY
  a.hospital_expire_flag
ORDER BY
  a.hospital_expire_flag DESC;