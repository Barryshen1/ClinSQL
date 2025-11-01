WITH female_icu_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    i.los,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
)

SELECT
  hospital_expire_flag,
  COUNT(*) AS num_admissions,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(STDDEV(los), 2) AS sd_los,
  ROUND(100 * SUM(CASE WHEN los < 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_lt_7_days
FROM
  female_icu_admissions
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;