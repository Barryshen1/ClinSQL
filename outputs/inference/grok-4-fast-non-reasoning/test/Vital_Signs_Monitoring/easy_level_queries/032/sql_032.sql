WITH first_icu_stays AS (
  -- Select first ICU stay per subject (rank by intime)
  SELECT 
    icu.subject_id,
    icu.stay_id,
    icu.hadm_id,
    pat.gender,
    pat.anchor_age,
    icu.intime,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
),
rr_items AS (
  -- Identify respiratory rate itemids
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
first_24h_rr AS (
  -- Respiratory rates in first 24h of first ICU stay
  SELECT 
    f.subject_id,
    f.stay_id,
    f.gender,
    f.anchor_age,
    f.intime,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM first_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON f.subject_id = ce.subject_id
    AND f.stay_id = ce.stay_id
  JOIN rr_items ri
    ON ce.itemid = ri.itemid
  WHERE ce.charttime >= f.intime
    AND ce.charttime < f.intime + INTERVAL 24 HOUR
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND f.rn = 1  -- First stay only
)
-- Compute max RR per patient-stay, for 38-48yo females (highlights 43yo)
SELECT 
  subject_id,
  stay_id,
  gender,
  anchor_age,
  MAX(valuenum) AS max_respiratory_rate_first_24h
FROM first_24h_rr
GROUP BY subject_id, stay_id, gender, anchor_age
ORDER BY anchor_age, subject_id;