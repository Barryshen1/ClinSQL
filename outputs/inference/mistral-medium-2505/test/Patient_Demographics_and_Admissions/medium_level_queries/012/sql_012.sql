WITH male_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Death'
      WHEN a.discharge_location LIKE '%Home%' THEN 'Discharged Home'
      WHEN a.discharge_location LIKE '%Facility%' OR
           a.discharge_location LIKE '%Nursing%' OR
           a.discharge_location LIKE '%Rehab%' THEN 'Discharged to Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
)

SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge7_count,
  ROUND(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*), 4) AS proportion_los_ge7,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM
  male_admissions
WHERE
  los_days IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;