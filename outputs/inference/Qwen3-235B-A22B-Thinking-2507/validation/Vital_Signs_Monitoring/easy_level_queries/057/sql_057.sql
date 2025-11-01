WITH filtered_stays AS (
  SELECT 
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients pat
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON pat.subject_id = icu.subject_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year)) BETWEEN 35 AND 45
),
resp_rates AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS resp_rate
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN filtered_stays fs
    ON ce.stay_id = fs.stay_id
  WHERE 
    ce.itemid = 220210  -- Standard itemid for Respiratory Rate
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude non-physiological values
),
max_per_stay AS (
  SELECT 
    stay_id,
    MAX(resp_rate) AS max_resp_rate
  FROM resp_rates
  GROUP BY stay_id
)
SELECT 
  MIN(max_resp_rate) AS min_of_max_resp_rate
FROM max_per_stay;