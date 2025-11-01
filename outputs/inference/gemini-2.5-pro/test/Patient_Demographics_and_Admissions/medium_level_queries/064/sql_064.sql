WITH
  -- Step 1: Join tables and calculate total ICU LOS for each hospital admission
  -- for the specified patient cohort.
  admission_icu_los AS (
    SELECT
      adm.hadm_id,
      adm.discharge_location,
      adm.hospital_expire_flag,
      SUM(icu.los) AS total_icu_los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON adm.hadm_id = icu.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 63 AND 73
    GROUP BY
      adm.hadm_id,
      adm.discharge_location,
      adm.hospital_expire_flag
  ),

  -- Step 2: Categorize admissions based on their discharge outcome.
  admission_outcomes AS (
    SELECT
      hadm_id,
      total_icu_los_days,
      CASE
        WHEN hospital_expire_flag = 1
          THEN 'In-hospital Death'
        WHEN discharge_location LIKE 'HOME%'
          THEN 'Home'
        WHEN discharge_location LIKE '%HOSPICE%'
          THEN 'Hospice'
        ELSE NULL
      END AS discharge_outcome
    FROM admission_icu_los
  )

-- Step 3: Group by the defined outcomes and calculate the final metrics.
SELECT
  discharge_outcome,
  COUNT(hadm_id) AS n_admissions,
  AVG(total_icu_los_days) AS mean_los,
  APPROX_QUANTILES(total_icu_los_days, 100)[OFFSET(50)] AS median_los,
  SAFE_DIVIDE(
    COUNTIF(total_icu_los_days <= 10), COUNT(hadm_id)
  ) * 100 AS percent_los_lte_10
FROM admission_outcomes
WHERE
  discharge_outcome IS NOT NULL -- Filter for only the specified outcomes
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;