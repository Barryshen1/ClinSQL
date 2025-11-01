WITH cohort AS (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      WHEN a.discharge_location = 'HOME' THEN 'home'
      ELSE NULL
    END AS discharge_cat,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_location = 'TRANSFER'
    AND a.dischtime IS NOT NULL
    AND (
      a.hospital_expire_flag = 1
      OR a.discharge_location LIKE '%HOSPICE%'
      OR a.discharge_location = 'HOME'
    )  -- Equivalent to discharge_cat IS NOT NULL
)
SELECT
  discharge_cat,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) AS patients_ge7_days,
  ROUND(
    SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*),
    3
  ) AS proportion_ge7,
  (SELECT APPROX_QUANTILES(los, 100)[OFFSET(7)] FROM cohort) AS seventh_percentile_los_days
FROM
  cohort
GROUP BY
  discharge_cat
ORDER BY
  CASE discharge_cat
    WHEN 'in-hospital death' THEN 1
    WHEN 'hospice' THEN 2
    WHEN 'home' THEN 3
  END;