SELECT
  CASE
    WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
    ELSE 'Discharged alive'
  END AS outcome_group,
  AVG(i.los) AS mean_los_days,
  STDDEV_SAMP(i.los) AS sd_los_days,
  100.0 * SUM(CASE WHEN i.los < 7 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_lt_7
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` AS i
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON i.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
WHERE
  LOWER(p.gender) = 'f'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 35 AND 45
  AND i.los IS NOT NULL
GROUP BY
  CASE
    WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
    ELSE 'Discharged alive'
  END
ORDER BY
  outcome_group;