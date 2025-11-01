WITH stepdown_stays AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    (ie.first_careunit = 'Step Down' OR ie.last_careunit = 'Step Down')
    AND p.gender = 'M'
    -- Calculate age at ICU admission: anchor_age + (ICU admission year - anchor_year)
    AND p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) BETWEEN 49 AND 59
),

diastolic_bp_per_stay AS (
  SELECT 
    s.stay_id,
    AVG(ch.valuenum) AS mean_diastolic_bp
  FROM stepdown_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch
    ON s.stay_id = ch.stay_id
    AND ch.itemid IN (220180, 225310, 224643, 227242)  -- Diastolic BP itemids
    AND ch.valuenum IS NOT NULL  -- Ensure numeric values
  GROUP BY s.stay_id
)

SELECT 
  APPROX_QUANTILES(mean_diastolic_bp, 100)[OFFSET(25)] AS q25,
  APPROX_QUANTILES(mean_diastolic_bp, 100)[OFFSET(75)] AS q75,
  APPROX_QUANTILES(mean_diastolic_bp, 100)[OFFSET(75)] - APPROX_QUANTILES(mean_diastolic_bp, 100)[OFFSET(25)] AS iqr
FROM diastolic_bp_per_stay;