WITH cohort AS (
  SELECT
    adm.hadm_id,
    -- Calculate LOS in fractional days for precision
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    -- Categorize discharge outcome based on flags and location descriptions
    CASE
      WHEN adm.hospital_expire_flag = 1
        THEN 'In-hospital Death'
      WHEN adm.discharge_location LIKE 'HOME%'
        THEN 'Home'
      WHEN adm.discharge_location IN (
        'SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP',
        'LONG TERM CARE HOSPITAL', 'CHRONIC/LONG TERM CARE', 'HOSPICE'
      )
        THEN 'Facility'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 86 AND 96
    AND adm.admission_type = 'URGENT'
    AND adm.insurance = 'Medicare'
    AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
)
SELECT
  discharge_outcome,
  AVG(los_days) AS los_mean,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_median,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS los_p90,
  -- Calculate the proportion of stays that are <= 10 days long.
  -- This represents the cumulative distribution, or percentile, of a 10-day stay.
  COUNTIF(los_days <= 10) / COUNT(hadm_id) AS percentile_of_10_day_stay
FROM
  cohort
WHERE
  discharge_outcome IN ('Home', 'Facility', 'In-hospital Death')
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;