SELECT
  hospital_expire_flag,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los, 2)[OFFSET(1)], 2) AS median_los,
  ROUND(100 * SUM(CASE WHEN los <= 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_le_5d
FROM (
  SELECT
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND (
      LOWER(a.admission_location) LIKE '%emergency room%'
      OR LOWER(a.admission_location) LIKE '%emergency department%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;