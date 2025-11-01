WITH first_ph AS (
  SELECT 
    ce.valuenum AS ph_value
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE 
    pat.gender = 'F'
    AND ce.itemid = 220274  -- Arterial pH itemid
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 6 HOUR)
    AND ce.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY icu.stay_id 
    ORDER BY ce.charttime ASC
  ) = 1
)
SELECT 
  APPROX_QUANTILES(ph_value, 2)[SAFE_OFFSET(1)] AS median_ph
FROM first_ph;