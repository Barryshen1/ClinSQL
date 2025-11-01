WITH hfnc_stays AS (
  -- Identify stays where High Flow Nasal Cannula was used
  SELECT DISTINCT ce.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%high flow nasal cannula%'
),

cohort AS (
  -- Identify female patients aged 81–91 at time of ICU stay
  SELECT ie.stay_id, ie.subject_id, ie.intime, ie.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM ie.intime) - pat.anchor_year) BETWEEN 81 AND 91
    AND ie.stay_id IN (SELECT stay_id FROM hfnc_stays)
),

systolic_bp AS (
  -- Extract systolic BP values during ICU stay
  SELECT ce.stay_id, AVG(ce.valuenum) AS mean_systolic
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN cohort co
    ON ce.stay_id = co.stay_id
  WHERE LOWER(di.label) LIKE '%systolic%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN co.intime AND co.outtime
  GROUP BY ce.stay_id
)

-- Final result: minimum of mean systolic BP across all qualifying stays
SELECT MIN(mean_systolic) AS min_per_stay_mean_systolic_bp
FROM systolic_bp;