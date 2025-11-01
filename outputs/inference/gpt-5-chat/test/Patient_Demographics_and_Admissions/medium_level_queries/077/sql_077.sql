WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND UPPER(a.admission_location) LIKE 'EMERGENCY%'
    AND a.dischtime IS NOT NULL
)
SELECT
  hospital_expire_flag,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los, 2)[OFFSET(1)], 2) AS median_los,
  ROUND(100 * SUM(CASE WHEN los <= 5 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_los_le_5
FROM
  cohort
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;