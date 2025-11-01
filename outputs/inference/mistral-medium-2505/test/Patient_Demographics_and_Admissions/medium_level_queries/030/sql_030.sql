WITH female_patients_44_54 AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 44 AND 54
),

elective_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients_44_54 p ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'ELECTIVE'
    AND a.dischtime IS NOT NULL
)

SELECT
  CASE
    WHEN hospital_expire_flag = 0 THEN 'Discharged Alive'
    WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
    ELSE 'Unknown'
  END AS discharge_status,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(PERCENTILE_DISC(los_days, 0.25) OVER(), 2) AS percentile_25,
  ROUND(PERCENTILE_DISC(los_days, 0.5) OVER(), 2) AS percentile_50,
  ROUND(PERCENTILE_DISC(los_days, 0.75) OVER(), 2) AS percentile_75,
  ROUND(PERCENTILE_DISC(los_days, 0.9) OVER(), 2) AS percentile_90
FROM
  elective_admissions
GROUP BY
  discharge_status,
  percentile_25,
  percentile_50,
  percentile_75,
  percentile_90
ORDER BY
  discharge_status;