WITH
-- Age at ICU admission for matching population
age_at_admit AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
),

-- Filtered population: female, age 75-85
eligible_pop AS (
  SELECT
    ci.subject_id,
    ci.hadm_id,
    ci.stay_id,
    ci.intime,
    ci.outtime,
    ci.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ci
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON adm.hadm_id = ci.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON pat.subject_id = ci.subject_id
  JOIN age_at_admit age
    ON age.subject_id = ci.subject_id AND age.hadm_id = ci.hadm_id
  WHERE pat.gender = 'F'
    AND age.age_at_admit BETWEEN 75 AND 85
),

-- Ventilation signal: evidence of ventilation within 0-48h
ventilated AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    e.intime,
    e.outtime,
    e.los
  FROM eligible_pop e
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON di.itemid = ce.itemid
    WHERE ce.subject_id = e.subject_id
      AND ce.hadm_id = e.hadm_id
      AND ce.stay_id = e.stay_id
      AND ce.charttime >= e.intime
      AND ce.charttime < TIMESTAMP_ADD(e.intime, INTERVAL 48 HOUR)
      AND LOWER(di.label) LIKE '%vent'
  )
),

-- Instability components within 0-48h
instability AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.intime,
    v.outtime,
    v.los,
    -- Hypotension: MAP < 65 within 48h
    (SELECT IFNULL(MAX(1), 0)
     FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
     JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
     WHERE ce.subject_id = v.subject_id
       AND ce.hadm_id = v.hadm_id
       AND ce.stay_id = v.stay_id
       AND ce.charttime >= v.intime
       AND ce.charttime < TIMESTAMP_ADD(v.intime, INTERVAL 48 HOUR)
       AND LOWER(di.label) LIKE '%mean arterial pressure%'
       AND ce.valuenum IS NOT NULL
       AND ce.valuenum < 65) AS hypotension_present,
    -- Tachycardia: HR > 100 within 48h
    (SELECT IFNULL(MAX(1), 0)
     FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
     JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
     WHERE ce.subject_id = v.subject_id
       AND ce.hadm_id = v.hadm_id
       AND ce.stay_id = v.stay_id
       AND ce.charttime >= v.intime
       AND ce.charttime < TIMESTAMP_ADD(v.intime, INTERVAL 48 HOUR)
       AND (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%')
       AND ce.valuenum IS NOT NULL
       AND ce.valuenum > 100) AS tachycardia_present
  FROM ventilated v
),

-- Instability score per stay
scores AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    i.hypotension_present,
    i.tachycardia_present,
    (i.hypotension_present + i.tachycardia_present) AS instability_score
  FROM instability i
),

-- Thresholds: compute 75th and 90th percentiles using APPROX_QUANTILES
thresholds AS (
  SELECT
    quant[OFFSET(75)] AS q75,
    quant[OFFSET(90)] AS q90
  FROM (
    SELECT APPROX_QUANTILES(instability_score, 100) AS quant
    FROM scores
  )
),

-- Top quartile cohort (instability_score >= q75)
top_quart AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    s.instability_score,
    s.hypotension_present,
    s.tachycardia_present,
    adm.hospital_expire_flag
  FROM scores s
  JOIN thresholds t ON 1=1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON adm.hadm_id = s.hadm_id
  WHERE s.instability_score >= t.q75
)

SELECT
  th.q90 AS instability_90th_percentile,
  AVG(tq.hypotension_present) AS hypotension_top_quartile_rate,
  AVG(tq.tachycardia_present) AS tachycardia_top_quartile_rate,
  MEDIAN(tq.los) AS median_icu_los_top_quartile_hours,
  AVG(CAST(tq.hospital_expire_flag = 1 AS INT64)) AS mortality_top_quartile
FROM top_quart tq
CROSS JOIN thresholds th;