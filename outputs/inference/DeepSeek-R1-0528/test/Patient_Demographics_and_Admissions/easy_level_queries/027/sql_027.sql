WITH first_admission AS (
  SELECT 
    p.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (
      PARTITION BY p.subject_id 
      ORDER BY a.admittime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.dischtime >= a.admittime  -- Ensure valid LOS
),
los_values AS (
  SELECT los_days
  FROM first_admission
  WHERE rn = 1  -- Select first admission per patient
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] 
  - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr
FROM los_values;