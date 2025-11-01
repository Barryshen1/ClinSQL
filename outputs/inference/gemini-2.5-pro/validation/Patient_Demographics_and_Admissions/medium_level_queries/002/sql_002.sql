WITH first_service AS (
  -- First, find the initial service for each hospital admission
  SELECT
    hadm_id,
    curr_service
  FROM (
    SELECT
      hadm_id,
      curr_service,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime ASC) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.services`
  )
  WHERE
    rn = 1
),
los_and_discharge AS (
  -- Next, build the cohort of patients and calculate LOS and discharge category
  SELECT
    -- Calculate Length of Stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    -- Categorize discharge location
    CASE
      WHEN adm.hospital_expire_flag = 1
        THEN 'In-Hospital Death'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'AGAINST MEDICAL ADVICE')
        THEN 'Home'
      WHEN adm.discharge_location IN (
        'SKILLED NURSING FACILITY',
        'REHAB/DISTINCT PART HOSP',
        'CHRONIC/LONG TERM CARE',
        'HOSPICE',
        'OTHER FACILITY',
        'ACUTE HOSPITAL'
      )
        THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    first_service AS fs
    ON adm.hadm_id = fs.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND fs.curr_service = 'MED'
    -- Ensure dischtime is not null for LOS calculation
    AND adm.dischtime IS NOT NULL
)
-- Final step: Aggregate the data to compute the requested statistics
SELECT
  discharge_group,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS los_p25,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS los_p50,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS los_p75,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS los_p90,
  ROUND(COUNTIF(los_days <= 10) * 100.0 / COUNT(*), 1) AS percent_los_lte_10
FROM
  los_and_discharge
WHERE
  discharge_group IN ('Home', 'Facility', 'In-Hospital Death')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;