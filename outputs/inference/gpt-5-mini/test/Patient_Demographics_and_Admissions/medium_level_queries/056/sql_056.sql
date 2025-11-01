SELECT
  CASE WHEN a.hospital_expire_flag = 1 THEN 'died' ELSE 'alive' END AS discharge_status,
  a.hospital_expire_flag AS hospital_expire_flag,
  COUNT(*) AS n_admissions,
  COUNTIF(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 7 * 24 * 3600) AS n_los_ge_7,
  ROUND(100.0 * COUNTIF(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 7 * 24 * 3600) / COUNT(*), 2) AS pct_los_ge_7,
  COUNTIF(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 14 * 24 * 3600) AS n_los_ge_14,
  ROUND(100.0 * COUNTIF(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 14 * 24 * 3600) / COUNT(*), 2) AS pct_los_ge_14,
  ROUND(100.0 * COUNTIF(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) <= 10 * 24 * 3600) / COUNT(*), 2) AS pct_at_or_below_10day_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 67 AND 77
  -- admission came from the ED (has ED registration time)
  AND a.edregtime IS NOT NULL
  -- require valid admission and discharge timestamps
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND a.dischtime > a.admittime
GROUP BY a.hospital_expire_flag
ORDER BY a.hospital_expire_flag;