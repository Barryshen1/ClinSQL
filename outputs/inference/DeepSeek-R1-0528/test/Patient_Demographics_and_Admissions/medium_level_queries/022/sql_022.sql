WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    -- Calculate LOS in days
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Define discharge categories
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN adm.discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN adm.discharge_location = 'HOME' THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
)

SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  AVG(los_days) AS mean_los,
  -- Calculate percentiles
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  -- Calculate % with LOS <= 10 days
  COUNTIF(los_days <= 10) / COUNT(*) * 100 AS pct_los_10_days
FROM
  cohort
WHERE
  discharge_category IN ('Home', 'Hospice', 'In-hospital death')
  AND age_at_admission BETWEEN 81 AND 91
GROUP BY
  discharge_category
ORDER BY
  discharge_category;