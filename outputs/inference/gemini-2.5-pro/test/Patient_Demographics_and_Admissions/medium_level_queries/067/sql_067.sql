WITH patient_cohort AS (
  -- Step 1: Identify male inpatients aged 49-59 who were on the medicine service
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    -- Calculate age at admission and filter
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 49 AND 59
    -- Filter for patients who were on the 'MED' service at any point during their stay
    AND adm.hadm_id IN (
      SELECT DISTINCT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.services`
      WHERE
        curr_service = 'MED'
    )
),

los_and_disposition AS (
  -- Step 2: For the cohort, calculate LOS and categorize discharge disposition
  SELECT
    cohort.hadm_id,
    -- Calculate LOS in days with fractions for accuracy
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    -- Categorize discharge location
    CASE
      WHEN adm.hospital_expire_flag = 1
        THEN 'In-Hospital Death'
      WHEN adm.discharge_location LIKE 'HOME%'
        THEN 'Home'
      WHEN adm.discharge_location = 'HOSPICE'
        THEN 'Hospice'
      ELSE NULL
    END AS discharge_disposition
  FROM
    patient_cohort AS cohort
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON cohort.hadm_id = adm.hadm_id
)

-- Step 3: Aggregate the data by discharge disposition and calculate the final metrics
SELECT
  discharge_disposition,
  COUNT(hadm_id) AS total_patients,
  SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(hadm_id)) AS proportion_los_ge_7,
  SAFE_DIVIDE(COUNTIF(los_days >= 14), COUNT(hadm_id)) AS proportion_los_ge_14,
  -- "7-day LOS percentile" is interpreted as the proportion of patients with LOS <= 7 days
  SAFE_DIVIDE(COUNTIF(los_days <= 7), COUNT(hadm_id)) AS percentile_rank_of_7_day_los
FROM
  los_and_disposition
WHERE
  -- Exclude patients who do not fall into the specified discharge categories
  discharge_disposition IS NOT NULL
GROUP BY
  discharge_disposition
ORDER BY
  discharge_disposition;