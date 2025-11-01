WITH admission_details AS (
  SELECT
    adm.hadm_id,
    -- Calculate length of stay in fractional days for precision
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24.0 * 60 * 60) AS los_days,
    -- Categorize the discharge outcome
    CASE
      WHEN adm.hospital_expire_flag = 1
      THEN 'In-hospital Death'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'ASSISTED LIVING')
      THEN 'Discharged Home'
      WHEN adm.discharge_location IN (
        'SKILLED NURSING FACILITY',
        'REHAB/DISTINCT PART HOSP',
        'CHRONIC/LONG TERM ACUTE CARE',
        'HOSPICE',
        'OTHER FACILITY',
        'PSYCHIATRIC HOSPITAL'
      )
      THEN 'Discharged to Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    -- Filter for patients aged 75-85 at the time of admission
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 75 AND 85
)
-- Aggregate results by discharge category
SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  -- Calculate the proportion of admissions with LOS >= 7 days
  SAFE_DIVIDE(
    COUNTIF(los_days >= 7),
    COUNT(*)
  ) AS proportion_los_ge_7_days,
  -- The percentile rank of a 7-day LOS is the proportion of admissions with LOS < 7
  SAFE_DIVIDE(
    COUNTIF(los_days < 7),
    COUNT(*)
  ) AS percentile_rank_of_7_day_los
FROM
  admission_details
-- Filter for only the specified discharge categories
WHERE
  discharge_category IN ('Discharged Home', 'Discharged to Facility', 'In-hospital Death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;