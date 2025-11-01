WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    -- Calculate LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Define discharge category
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      WHEN a.discharge_location IN ('SKILLED NURSING FACILITY', 'REHABILITATION', 'LONG TERM CARE HOSPITAL') THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'ELECTIVE'
)

SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  COUNTIF(los_days >= 7) AS count_los_ge7,
  COUNTIF(los_days >= 14) AS count_los_ge14,
  ROUND(COUNTIF(los_days >= 7) * 100.0 / COUNT(*), 2) AS pct_los_ge7,
  ROUND(COUNTIF(los_days >= 14) * 100.0 / COUNT(*), 2) AS pct_los_ge14
FROM
  cohort
WHERE
  age BETWEEN 70 AND 80
  AND discharge_category IN ('Home', 'Facility', 'In-hospital death')  -- Exclude 'Other'
GROUP BY
  discharge_category
ORDER BY
  discharge_category;