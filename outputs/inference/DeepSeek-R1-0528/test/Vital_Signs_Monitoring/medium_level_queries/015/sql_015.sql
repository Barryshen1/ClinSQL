WITH cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'EMERGENCY'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 59 AND 69
),
sbp_per_stay AS (
  SELECT
    c.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM
    cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON c.stay_id = ce.stay_id
      AND c.subject_id = ce.subject_id
  WHERE
    ce.itemid IN (220050, 220179)  -- SBP item IDs
    AND ce.valuenum IS NOT NULL    -- Ensure numeric value exists
    AND ce.charttime >= c.intime   -- During ICU stay
    AND ce.charttime <= c.outtime
  GROUP BY
    c.stay_id
)
SELECT
  APPROX_QUANTILES(max_sbp, 100)[OFFSET(75)] AS sbp_75th_percentile
FROM
  sbp_per_stay;