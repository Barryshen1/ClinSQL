SELECT
  hospital_expire_flag,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS std_los,
  AVG(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100 AS percent_los_le7
FROM (
  SELECT
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.edregtime IS NOT NULL
) subquery
GROUP BY hospital_expire_flag;