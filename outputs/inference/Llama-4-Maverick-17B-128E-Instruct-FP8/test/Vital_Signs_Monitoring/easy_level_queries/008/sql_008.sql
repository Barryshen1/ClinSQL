WITH 
-- Step 1: Identify itemid for respiratory rate
respiratory_rate_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Respiratory Rate%' OR abbreviation LIKE '%RR%'
),

-- Step 2 & 3: Filter patients and identify relevant ICU stays
relevant_icustays AS (
  SELECT icu.stay_id, icu.intime, pat.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M' AND pat.anchor_age BETWEEN 52 AND 62
  AND DATETIME_DIFF(icu.intime, DATETIME(DATE(pat.anchor_year, 1, 1)), YEAR) BETWEEN 52 AND 62
  AND DATETIME_ADD(icu.intime, INTERVAL 2 DAY) <= COALESCE(icu.outtime, DATETIME '9999-12-31 23:59:59')
),

-- Step 4: Query chartevents for respiratory rate on or after ICU day 2
respiratory_rates AS (
  SELECT MAX(ce.valuenum) AS max_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN relevant_icustays icu ON ce.stay_id = icu.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM respiratory_rate_itemid)
  AND ce.charttime >= DATETIME_ADD(icu.intime, INTERVAL 2 DAY)
)

-- Step 5: Calculate the maximum respiratory rate
SELECT max_rr
FROM respiratory_rates;