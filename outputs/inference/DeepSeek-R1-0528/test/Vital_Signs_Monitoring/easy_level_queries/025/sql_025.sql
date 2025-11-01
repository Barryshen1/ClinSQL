WITH filtered_stays AS (
  SELECT 
    icu.stay_id,
    DATE_DIFF(
      icu.intime, 
      -- Approximate birth date (Jan 1st of birth year)
      DATE(CAST(p.anchor_year - p.anchor_age AS INT), 1, 1), 
      YEAR
    ) AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
stays_with_resp AS (
  SELECT 
    fs.stay_id,
    AVG(ce.valuenum) AS mean_resp_rate
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220210, 224690)  -- Respiratory Rate item IDs
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND fs.age_at_icu_admission BETWEEN 39 AND 49
  GROUP BY fs.stay_id
)
SELECT 
  APPROX_QUANTILES(mean_resp_rate, 100)[OFFSET(75)] AS percentile_75_resp_rate
FROM stays_with_resp;