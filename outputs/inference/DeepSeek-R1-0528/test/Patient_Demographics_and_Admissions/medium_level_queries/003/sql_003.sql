WITH base AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission,
    -- Compute LOS in days
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Define discharge groups
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'Death'
      WHEN adm.discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
      WHEN adm.discharge_location = 'HOME' THEN 'Home'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND adm.admission_type IN ('ELECTIVE', 'URGENT')  -- Non-emergency only
)

SELECT
  discharge_category,
  COUNT(*) AS n,  -- Number of admissions
  AVG(los_days) AS mean_los,  -- Mean LOS
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25,  -- 25th percentile
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median,  -- Median
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,  -- 75th percentile
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,  -- 90th percentile
  ROUND(SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_lte_14_days  -- % LOS ≤14 days
FROM
  base
WHERE
  age_at_admission BETWEEN 80 AND 90  -- Age filter
  AND discharge_category IS NOT NULL  -- Only include Home/Hospice/Death
GROUP BY
  discharge_category
ORDER BY
  discharge_category;