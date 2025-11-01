WITH filtered_stays AS (
  SELECT 
    ie.stay_id,
    ie.intime,
    -- Calculate exact age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    -- Age filter (68-78 years)
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 68 AND 78
),
rr_data AS (
  SELECT 
    fs.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220210, 224690)  -- Respiratory Rate item IDs
    AND ce.valuenum IS NOT NULL    -- Exclude non-numeric values
    AND ce.charttime >= fs.intime  -- First 48 hours of ICU stay
    AND ce.charttime <= DATETIME_ADD(fs.intime, INTERVAL 48 HOUR)
  GROUP BY fs.stay_id
),
all_avg_rr AS (
  SELECT 
    avg_rr,
    -- Compute percentile rank (0-1) and convert to 0-100 scale
    PERCENT_RANK() OVER (ORDER BY avg_rr) * 100 AS percentile
  FROM rr_data
)
SELECT 
  percentile AS percentile_for_12_brpm
FROM all_avg_rr
WHERE avg_rr = 12  -- Target value for the patient
LIMIT 1;