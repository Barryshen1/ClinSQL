WITH first_stays AS (
  SELECT stay_id, subject_id, hadm_id, intime, los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE los >= 2
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) = 1
),
eligible_patients AS (
  SELECT fs.stay_id, fs.subject_id, fs.hadm_id, fs.intime
  FROM first_stays fs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fs.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),
bp_measurements AS (
  SELECT 
    ep.stay_id,
    ep.intime,
    ce.charttime,
    ce.valuenum AS systolic_bp
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ep.subject_id = ce.subject_id
    AND ep.hadm_id = ce.hadm_id
    AND ep.stay_id = ce.stay_id
  WHERE ce.itemid IN (220045, 220179)  -- Systolic BP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= ep.intime
    AND ce.charttime <= DATETIME_ADD(ep.intime, INTERVAL 48 HOUR)
),
stay_averages AS (
  SELECT 
    stay_id,
    AVG(systolic_bp) AS avg_systolic_bp_first_48h
  FROM bp_measurements
  GROUP BY stay_id
  HAVING COUNT(*) >= 1  -- Ensure at least one measurement
),
percentile_calc AS (
  SELECT 
    PERCENT_RANK() OVER (ORDER BY avg_systolic_bp_first_48h) AS percentile_150
  FROM stay_averages
  WHERE avg_systolic_bp_first_48h <= 150  -- Ranks relative to stays <=150
)
SELECT 
  ROUND(percentile_150 * 100, 2) AS percentile_for_150_mmhg
FROM percentile_calc
ORDER BY percentile_150 DESC
LIMIT 1;