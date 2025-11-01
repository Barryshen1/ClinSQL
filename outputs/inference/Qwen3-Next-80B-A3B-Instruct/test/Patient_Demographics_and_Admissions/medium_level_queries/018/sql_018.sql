WITH filtered_admissions AS (
  SELECT
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    p.anchor_age,
    p.gender,
    -- Calculate LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'TRANSFER FROM OTHER HOSP'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
grouped_discharge AS (
  SELECT
    CASE
      WHEN deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES') THEN 'Home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE', 'OTHER FACILITY', 'HOSPICE', 'PSYCH FACILITY') THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group,
    los
  FROM
    filtered_admissions
  WHERE
    CASE
      WHEN deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES') THEN 'Home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE', 'OTHER FACILITY', 'HOSPICE', 'PSYCH FACILITY') THEN 'Facility'
      ELSE 'Other'
    END IN ('Home', 'Facility', 'In-hospital death')
)
SELECT
  discharge_group,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS q1_los,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS q3_los,
  (SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS pct_le_10_days
FROM
  grouped_discharge
GROUP BY
  discharge_group
ORDER BY
  discharge_group;