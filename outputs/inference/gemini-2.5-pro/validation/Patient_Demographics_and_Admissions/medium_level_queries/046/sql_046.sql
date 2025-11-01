WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.los,
    -- Calculate patient age at the time of ICU admission
    (EXTRACT(YEAR FROM icu.intime) - p.anchor_year + p.anchor_age) AS age_at_icu_admission,
    -- Categorize the final disposition of the hospital admission
    CASE
      WHEN adm.hospital_expire_flag = 1
        THEN 'In-hospital Death'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'ASSISTED LIVING')
        THEN 'Home'
      WHEN adm.discharge_location IN (
        'SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP',
        'CHRONIC/LONG TERM CARE', 'HOSPICE', 'LONG TERM CARE HOSPITAL',
        'OTHER FACILITY'
      )
        THEN 'Facility'
      ELSE 'Other/Unknown'
    END AS outcome_category
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'F'
)
SELECT
  outcome_category,
  COUNT(stay_id) AS n,
  -- Format mean and standard deviation into a single "mean ± SD" string, rounded to one decimal
  FORMAT('%.1f ± %.1f', AVG(los), STDDEV(los)) AS mean_sd_los_days,
  -- Calculate the percentage of stays with LOS < 10 days, rounded to one decimal
  ROUND(AVG(
    CASE
      WHEN los < 10 THEN 100.0
      ELSE 0.0
    END
  ), 1) AS percent_los_lt_10
FROM
  cohort
WHERE
  age_at_icu_admission BETWEEN 87 AND 97
  AND outcome_category IN ('Home', 'Facility', 'In-hospital Death')
GROUP BY
  outcome_category
ORDER BY
  outcome_category;