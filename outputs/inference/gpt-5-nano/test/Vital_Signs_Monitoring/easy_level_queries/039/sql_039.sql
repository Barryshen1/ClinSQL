WITH resp_items AS (
  -- Identify respiratory-rate measurements in ICU: stay_id, time, and value
  SELECT ce.stay_id, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%respir%'  -- captures respiratory rate items
    AND ce.valuenum IS NOT NULL
),
first_charttime AS (
  -- For each ICU stay, get the earliest respiratory-rate charttime
  SELECT stay_id, MIN(charttime) AS first_charttime
  FROM resp_items
  GROUP BY stay_id
),
first_rr AS (
  -- Join back to get the actual first respiratory rate value for each stay
  SELECT fc.stay_id, ri.valuenum AS first_rr
  FROM first_charttime AS fc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ri
    ON ri.stay_id = fc.stay_id AND ri.charttime = fc.first_charttime
),
eligible AS (
  -- Apply age and gender filters: female, age at ICU admission between 51 and 61
  SELECT fr.first_rr
  FROM first_rr AS fr
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.stay_id = fr.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 51 AND 61
)
-- Compute the 25th percentile using 100 quantiles and take the 25th position
SELECT q[OFFSET(24)] AS p25
FROM (
  SELECT APPROX_QUANTILES(first_rr, 100) AS q
  FROM eligible
);