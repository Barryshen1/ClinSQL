WITH
  -- Step 1: Identify hospital admissions (hadm_id) with a sepsis diagnosis, excluding septic shock.
  sepsis_filtered_diagnoses AS (
    SELECT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    GROUP BY
      hadm_id
    HAVING
      -- The admission must have at least one diagnosis containing 'sepsis'
      COUNT(CASE WHEN LOWER(dd.long_title) LIKE '%sepsis%' THEN 1 END) > 0
      -- And must NOT have any diagnosis containing 'septic shock'
      AND COUNT(CASE WHEN LOWER(dd.long_title) LIKE '%septic shock%' THEN 1 END) = 0
  ),

  -- Step 2: Build the base cohort of male patients, aged 86-96, who meet the diagnosis criteria.
  cohort_base AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.deathtime,
      adm.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN
      sepsis_filtered_diagnoses AS sfd
      ON adm.hadm_id = sfd.hadm_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 86 AND 96
  ),

  -- Step 3: Identify admissions from our cohort that had an ICU stay starting within 24 hours of hospital admission.
  day1_icu AS (
    SELECT DISTINCT
      icu.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      cohort_base AS cb
      ON icu.hadm_id = cb.hadm_id
    WHERE
      icu.intime <= DATETIME_ADD(cb.admittime, INTERVAL 24 HOUR)
  ),

  -- Step 4: Combine all information and calculate per-patient metrics (LOS, days-to-death, ICU status).
  final_data AS (
    SELECT
      cb.hadm_id,
      cb.hospital_expire_flag,
      -- Calculate LOS in days, rounding up to the nearest full day.
      CEIL(DATETIME_DIFF(cb.dischtime, cb.admittime, HOUR) / 24.0) AS los_days,
      -- Calculate days from admission to death, only for patients who died.
      CASE
        WHEN cb.hospital_expire_flag = 1
        THEN DATE_DIFF(cb.deathtime, cb.admittime, DAY)
        ELSE NULL
      END AS days_to_death,
      -- Create a flag for whether the patient was in the ICU on day 1.
      CASE
        WHEN d1icu.hadm_id IS NOT NULL THEN 'ICU on Day 1'
        ELSE 'No ICU on Day 1'
      END AS day1_icu_status
    FROM
      cohort_base AS cb
    LEFT JOIN
      day1_icu AS d1icu
      ON cb.hadm_id = d1icu.hadm_id
  )

-- Step 5: Aggregate the results by LOS category and ICU status to compute the final metrics.
SELECT
  CASE
    WHEN fd.los_days <= 3 THEN '≤3 days'
    WHEN fd.los_days BETWEEN 4 AND 6 THEN '4–6 days'
    WHEN fd.los_days BETWEEN 7 AND 10 THEN '7–10 days'
    WHEN fd.los_days > 10 THEN '>10 days'
    ELSE 'Unknown'
  END AS los_category,
  fd.day1_icu_status,
  COUNT(DISTINCT fd.hadm_id) AS num_patients,
  SUM(fd.hospital_expire_flag) AS num_deaths,
  ROUND(
    100 * SAFE_DIVIDE(SUM(fd.hospital_expire_flag), COUNT(DISTINCT fd.hadm_id)),
    1
  ) AS mortality_percent,
  -- Calculate the median (50th percentile) of days to death. NULLs are ignored.
  APPROX_QUANTILES(fd.days_to_death, 100)[OFFSET(50)] AS median_days_to_death
FROM
  final_data AS fd
GROUP BY
  los_category,
  day1_icu_status
ORDER BY
  -- Sort by ICU status, then by LOS category in a logical, not alphabetical, order.
  day1_icu_status,
  CASE los_category
    WHEN '≤3 days' THEN 1
    WHEN '4–6 days' THEN 2
    WHEN '7–10 days' THEN 3
    WHEN '>10 days' THEN 4
    ELSE 5
  END;