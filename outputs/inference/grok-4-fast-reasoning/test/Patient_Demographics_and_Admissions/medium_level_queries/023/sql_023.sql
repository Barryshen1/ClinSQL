WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) AS age_at_adm,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location IN ('DISCHARGED TO HOME', 'LEFT AGAINST MEDICAL ADVICE') THEN 'home'
      ELSE 'facility'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.dischtime > a.admittime
)
SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  COUNTIF(los_days >= 7) / COUNT(*) AS proportion_los_ge7_days,
  (COUNTIF(los_days <= 10) / COUNT(*) * 100) AS percentile_rank_10day_los
FROM
  cohort
WHERE
  age_at_adm BETWEEN 41 AND 51
GROUP BY
  discharge_category
ORDER BY
  discharge_category;