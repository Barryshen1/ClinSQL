WITH cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime >= a.admittime
)

SELECT
  hospital_expire_flag,
  AVG(los_days) AS mean_los,
  PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY los_days) AS median_los,
  AVG(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) * 100 AS percent_los_le_5_days
FROM
  cohort
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;