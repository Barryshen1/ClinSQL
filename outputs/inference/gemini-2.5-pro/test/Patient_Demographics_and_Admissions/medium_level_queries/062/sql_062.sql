WITH admission_details AS (
  SELECT
    -- Calculate hospital length of stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Categorize discharge destination
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOME / HOSPICE') THEN 'Home'
      WHEN adm.discharge_location IN (
        'SKILLED NURSING FACILITY',
        'REHAB/DISTINCT PART HOSP',
        'LONG TERM CARE HOSPITAL',
        'CHRONIC/LONG TERM CARE'
      ) THEN 'SNF/Rehab/LTACH'
      ELSE NULL
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    -- Filter for male patients
    pat.gender = 'M'
    -- Calculate and filter for age at admission
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 64 AND 74
    -- Ensure valid timestamps for LOS calculation
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  discharge_group,
  -- Calculate the proportion of patients with LOS of 7 days or more
  SAFE_DIVIDE(
    COUNTIF(los_days >= 7),
    COUNT(*)
  ) AS proportion_los_ge_7_days,
  -- Calculate the 14th percentile of LOS for the group. APPROX_QUANTILES returns an array
  -- of 101 values (min, 99 percentiles, max); OFFSET(14) retrieves the 14th percentile.
  APPROX_QUANTILES(los_days, 100)[OFFSET(14)] AS los_14th_percentile_days
FROM
  admission_details
WHERE
  -- Exclude admissions that do not fall into the specified discharge categories
  discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  discharge_group;