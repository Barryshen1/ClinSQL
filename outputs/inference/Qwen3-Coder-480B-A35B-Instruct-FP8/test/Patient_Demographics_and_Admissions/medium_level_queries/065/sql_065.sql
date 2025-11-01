WITH non_icu_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  WHERE
    NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_icu.icustays icu
      WHERE icu.hadm_id = a.hadm_id
    )
),
filtered_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),
admissions_with_los AS (
  SELECT
    a.hadm_id,
    a.dischtime,
    a.admittime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
      WHEN a.discharge_location LIKE '%HOME%' THEN 'Discharged Home'
      WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'Discharged to Hospice'
      ELSE NULL
    END AS discharge_category
  FROM
    non_icu_admissions a
  JOIN
    filtered_patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    a.admittime < a.dischtime
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS stddev_los
FROM
  admissions_with_los
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;