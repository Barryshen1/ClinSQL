WITH cohort_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 63 AND 73
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = i.hadm_id
        AND d.icd_code LIKE 'G40.5%'
    )
),

cohort_events AS (
  SELECT 
    c.stay_id,
    COUNTIF(ce.itemid = 220045 AND ce.valuenum > 100) AS tachycardia_count,
    COUNTIF(ce.itemid = 220045) AS tachycardia_total,
    COUNTIF(ce.itemid = 220052 AND ce.valuenum < 65) AS hypotension_count,
    COUNTIF(ce.itemid = 220052) AS hypotension_total
  FROM cohort_stays c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND c.intime + INTERVAL 72 HOUR
  GROUP BY c.stay_id
),

cohort_metrics AS (
  SELECT 
    AVG(COALESCE(tachycardia_count / NULLIF(tachycardia_total, 0), 0)) AS tachycardia_burden,
    AVG(COALESCE(hypotension_count / NULLIF(hypotension_total, 0), 0)) AS map_burden,
    AVG(TIMESTAMP_DIFF(outtime, intime, HOUR)) AS los_hours,
    AVG(a.hospital_expire_flag) AS mortality
  FROM cohort_stays c
  LEFT JOIN cohort_events ce ON c.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON c.hadm_id = a.hadm_id
),

general_icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),

general_events AS (
  SELECT 
    g.stay_id,
    COUNTIF(ce.itemid = 220045 AND ce.valuenum > 100) AS tachycardia_count,
    COUNTIF(ce.itemid = 220045) AS tachycardia_total,
    COUNTIF(ce.itemid = 220052 AND ce.valuenum < 65) AS hypotension_count,
    COUNTIF(ce.itemid = 220052) AS hypotension_total
  FROM general_icu_stays g
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON g.stay_id = ce.stay_id
    AND ce.charttime BETWEEN g.intime AND g.intime + INTERVAL 72 HOUR
  GROUP BY g.stay_id
),

general_metrics AS (
  SELECT 
    AVG(COALESCE(tachycardia_count / NULLIF(tachycardia_total, 0), 0)) AS tachycardia_burden,
    AVG(COALESCE(hypotension_count / NULLIF(hypotension_total, 0), 0)) AS map_burden,
    AVG(TIMESTAMP_DIFF(outtime, intime, HOUR)) AS los_hours,
    AVG(a.hospital_expire_flag) AS mortality
  FROM general_icu_stays g
  LEFT JOIN general_events ge ON g.stay_id = ge.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON g.hadm_id = a.hadm_id
),

cohort_vital_index AS (
  SELECT 
    AVG(tachycardia_count + hypotension_count) AS mean_vital_index,
    APPROX_QUANTILES(tachycardia_count + hypotension_count, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(tachycardia_count + hypotension_count, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(tachycardia_count + hypotension_count, 4)[OFFSET(3)] AS p75,
    APPROX_QUANTILES(tachycardia_count + hypotension_count, 4)[OFFSET(4)] AS p90
  FROM cohort_events
)

SELECT 
  cv.mean_vital_index,
  cv.p25,
  cv.p50,
  cv.p75,
  cv.p90,
  cm.tachycardia_burden AS cohort_tachycardia,
  gm.tachycardia_burden AS general_tachycardia,
  cm.map_burden AS cohort_map,
  gm.map_burden AS general_map,
  cm.los_hours AS cohort_los,
  gm.los_hours AS general_los,
  cm.mortality AS cohort_mortality,
  gm.mortality AS general_mortality
FROM cohort_vital_index cv
CROSS JOIN cohort_metrics cm
CROSS JOIN general_metrics gm;