WITH cohort_stays AS (
  SELECT
    icu.los,
    -- Categorize discharge outcome, prioritizing death.
    CASE
      WHEN adm.hospital_expire_flag = 1
      THEN 'In-hospital Death'
      WHEN adm.discharge_location = 'HOSPICE'
      THEN 'Hospice'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE')
      THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    -- Filter for female patients
    p.gender = 'F'
    -- Filter for age at ICU admission between 40 and 50
    AND (
      p.anchor_age + DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)
    ) BETWEEN 40 AND 50
)
SELECT
  discharge_outcome,
  -- Calculate approximate percentiles for Length of Stay (LOS)
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS los_p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS los_p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS los_p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS los_p95,
  -- Calculate the percentage of stays with LOS less than or equal to 7 days
  AVG(IF(los <= 7, 1.0, 0.0)) * 100 AS pct_los_le_7_days
FROM
  cohort_stays
WHERE
  -- Only include the specified discharge outcomes
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;