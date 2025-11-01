WITH cohort AS (
  -- First, define the patient cohort based on age and admission type, and calculate LOS.
  SELECT
    adm.hadm_id,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate LOS in fractional days for higher precision in stats
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  WHERE
    -- Filter for elective admissions as a proxy for postoperative patients
    adm.admission_type = 'ELECTIVE'
    -- Calculate age at admission and filter for the 88-98 range
    AND ((EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 88 AND 98
    -- Ensure a discharge time exists to calculate a valid LOS
    AND adm.dischtime IS NOT NULL
),
discharge_categorized AS (
  -- Second, categorize each admission by its discharge outcome.
  SELECT
    c.los_days,
    CASE
      WHEN c.hospital_expire_flag = 1 THEN 'In-hospital Death'
      WHEN c.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      WHEN c.discharge_location IN (
        'SKILLED NURSING FACILITY',
        'REHAB/DISTINCT PART HOSP',
        'LONG TERM CARE HOSPITAL',
        'CHRONIC/LONG TERM CARE'
      ) THEN 'SNF/Rehab/LTACH'
      ELSE 'Other' -- Group all other outcomes here
    END AS discharge_outcome
  FROM
    cohort AS c
)
-- Finally, aggregate the data to compute the requested statistics for each outcome category.
SELECT
  discharge_outcome,
  COUNT(*) AS number_of_admissions,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
  SAFE_DIVIDE(COUNTIF(los_days <= 7) * 100.0, COUNT(*)) AS percent_los_leq_7_days
FROM
  discharge_categorized
WHERE
  -- Exclude 'Other' outcomes to focus on the requested categories
  discharge_outcome IN ('Home', 'SNF/Rehab/LTACH', 'In-hospital Death')
GROUP BY
  discharge_outcome
ORDER BY
  -- Order results for logical presentation
  CASE discharge_outcome
    WHEN 'Home' THEN 1
    WHEN 'SNF/Rehab/LTACH' THEN 2
    WHEN 'In-hospital Death' THEN 3
  END;