WITH PatientStays AS (
  -- First, select and filter the relevant hospital admissions for the specified cohort
  SELECT
    adm.hadm_id,
    -- Calculate the hospital length of stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Categorize the discharge destination based on the question's criteria
    CASE
      WHEN adm.hospital_expire_flag = 1
      THEN 'In-Hospital Death'
      WHEN adm.discharge_location LIKE 'HOME%'
      THEN 'Home'
      WHEN adm.discharge_location IN (
        'SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP',
        'LONG TERM CARE HOSPITAL', 'HOSPICE', 'ACUTE HOSPITAL',
        'OTHER FACILITY', 'PSYCHIATRIC HOSPITAL', 'CHRONIC/LONG TERM CARE'
      )
      THEN 'Facility'
      ELSE NULL -- Other destinations like 'AGAINST MEDICAL ADVICE' will be excluded later
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    -- Filter for male patients aged 43-53
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    -- Filter for patients transferred from another hospital
    AND adm.admission_location = 'TRANSFER FROM ANOTHER HOSPITAL'
    -- Ensure a length of stay can be calculated
    AND adm.dischtime IS NOT NULL
)
-- Now, aggregate the results by the discharge category to compute the final metrics
SELECT
  discharge_category,
  COUNT(hadm_id) AS number_of_admissions,
  -- Calculate median LOS using approximate quantiles for efficiency
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  -- Calculate Interquartile Range (IQR) as the 75th percentile minus the 25th
  (
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)]
  ) AS iqr_los_days,
  -- Calculate the percentage of stays that were 10 days or shorter
  ROUND(COUNTIF(los_days <= 10) * 100.0 / COUNT(hadm_id), 2) AS percent_los_lte_10
FROM
  PatientStays
-- Exclude admissions that did not match our defined discharge categories
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;