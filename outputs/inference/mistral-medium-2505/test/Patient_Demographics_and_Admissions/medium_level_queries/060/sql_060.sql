WITH female_ed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    -- Calculate length of stay in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    -- Female patients
    p.gender = 'F'
    -- Age 50-60 at admission
    AND p.anchor_age BETWEEN 50 AND 60
    -- Admitted from ED
    AND a.admission_location LIKE '%EMERGENCY%'
    -- Complete admission records
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

discharge_categories AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    female_ed_admissions
)

SELECT
  discharge_outcome,
  COUNT(*) AS patient_count,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(STDDEV(los_days), 2) AS sd_los,
  ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_le_10_days
FROM
  discharge_categories
GROUP BY
  discharge_outcome
ORDER BY
  patient_count DESC;