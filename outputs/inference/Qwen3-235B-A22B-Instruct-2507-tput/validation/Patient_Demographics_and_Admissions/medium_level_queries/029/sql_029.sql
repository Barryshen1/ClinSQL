SELECT
  adm.hospital_expire_flag,
  ROUND(AVG(icu.los), 2) AS mean_los,
  ROUND(STDDEV(icu.los), 2) AS sd_los,
  ROUND(100.0 * SUM(CASE WHEN icu.los < 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_lt_7_days
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` AS icu
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  USING (hadm_id)
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON pat.subject_id = adm.subject_id
WHERE
  pat.gender = 'F'
  AND adm.admittime IS NOT NULL
  AND pat.anchor_year IS NOT NULL
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 35 AND 45
GROUP BY
  adm.hospital_expire_flag
ORDER BY
  adm.hospital_expire_flag;