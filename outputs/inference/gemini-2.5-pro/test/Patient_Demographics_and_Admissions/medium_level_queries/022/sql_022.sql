WITH cohort AS (
  SELECT
    -- Calculate hospital length of stay in days.
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,

    -- Categorize discharge destination into the groups of interest.
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'In-Hospital Death'
      WHEN adm.discharge_location = 'HOSPICE' THEN 'Hospice'
      -- Group 'HOME' and 'HOME HEALTH CARE' together.
      WHEN adm.discharge_location LIKE 'HOME%' THEN 'Home'
      ELSE NULL
    END AS discharge_group

  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  WHERE
    -- Filter for male patients.
    p.gender = 'M'
    -- Filter for patients admitted as a transfer from another hospital.
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    -- Calculate age at admission for filtering, as anchor_age is fixed.
    AND (p.anchor_age + EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 81 AND 91
    -- Ensure LOS is calculable.
    AND adm.dischtime IS NOT NULL
)
SELECT
  discharge_group,
  ROUND(AVG(los_days), 2) AS mean_los,
  -- APPROX_QUANTILES is an efficient way to calculate multiple percentiles.
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  -- Calculate the percentage of stays less than or equal to 10 days.
  ROUND(100.0 * COUNTIF(los_days <= 10) / COUNT(*), 2) AS percent_los_lte_10
FROM
  cohort
WHERE
  -- Exclude any admissions that do not fall into our target discharge categories.
  discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  -- Order results for clear presentation.
  discharge_group;