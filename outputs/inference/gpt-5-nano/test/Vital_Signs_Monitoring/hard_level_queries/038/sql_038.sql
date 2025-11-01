WITH target_ids AS (
  SELECT DISTINCT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dic
    ON i.subject_id = dic.subject_id AND i.hadm_id = dic.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON dic.icd_code = di.icd_code
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 63 AND 73
    AND LOWER(di.long_title) LIKE '%status epilepticus%'
),

base_stays AS (
  -- all ICU stays with intime and LOS we will use
  SELECT s.stay_id,
         s.subject_id,
         s.hadm_id,
         s.intime,
         s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
),

-- Counts and burdens for vital-sign observations within the first 72 hours
counts_by_stay AS (
  SELECT b.stay_id,
         b.subject_id,
         b.hadm_id,
         b.intime,
         b.los,
         SUM(CASE WHEN LOWER(di.label) LIKE '%heart rate%' THEN 1 ELSE 0 END) AS hr_total,
         SUM(CASE WHEN LOWER(di.label) LIKE '%heart rate%' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachy_count,
         SUM(CASE WHEN LOWER(di.label) LIKE '%mean arterial pressure%' THEN 1 ELSE 0 END) AS map_total,
         SUM(CASE WHEN LOWER(di.label) LIKE '%mean arterial pressure%' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_below65
  FROM base_stays b
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = b.stay_id
   AND ce.charttime >= b.intime
   AND ce.charttime < TIMESTAMP_ADD(b.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  GROUP BY b.stay_id, b.subject_id, b.hadm_id, b.intime, b.los
),

per_stay AS (
  SELECT c.stay_id,
         c.subject_id,
         c.hadm_id,
         c.intime,
         c.los,
         c.hr_total,
         c.tachy_count,
         c.map_total,
         c.map_below65,
         -- Burdens (0 if no observations)
         CASE WHEN c.hr_total > 0 THEN CAST(c.tachy_count AS FLOAT64) / c.hr_total ELSE 0 END AS tachy_proportion,
         CASE WHEN c.map_total > 0 THEN CAST(c.map_below65 AS FLOAT64) / c.map_total ELSE 0 END AS map_proportion,
         -- Vital-instability index (average of the two burdens)
         CASE
           WHEN c.hr_total > 0 OR c.map_total > 0 THEN
             (CASE WHEN c.hr_total > 0 THEN CAST(c.tachy_count AS FLOAT64) / c.hr_total ELSE 0 END +
              CASE WHEN c.map_total > 0 THEN CAST(c.map_below65 AS FLOAT64) / c.map_total ELSE 0 END) / 2
           ELSE 0
         END AS vital_instability_index,
         -- Mortality indicator (in-hospital death)
         CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality
  FROM counts_by_stay c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
),

target_per_stay AS (
  SELECT ps.*
  FROM per_stay ps
  JOIN target_ids t ON ps.stay_id = t.stay_id
),

general_per_stay AS (
  SELECT ps.*
  FROM per_stay ps
),

-- Summary statistics for the target cohort
target_summ AS (
  SELECT
     AVG(vital_instability_index) AS mean_vi,
     AVG(tachy_proportion) AS mean_tachy_burden,
     AVG(map_proportion) AS mean_map_burden,
     AVG(los) AS mean_los,
     AVG(mortality) AS mortality_rate
  FROM target_per_stay
),

-- Quantiles for the target cohort (using APPROX_QUANTILES and indexing)
target_quants AS (
  SELECT
     quantiles[OFFSET(25)] AS p25_vi,
     quantiles[OFFSET(50)] AS p50_vi,
     quantiles[OFFSET(75)] AS p75_vi,
     quantiles[OFFSET(90)] AS p90_vi
  FROM (
     SELECT APPROX_QUANTILES(vital_instability_index, 100) AS quantiles
     FROM target_per_stay
  )
),

-- Summary statistics for the general ICU population
general_summ AS (
  SELECT
     AVG(vital_instability_index) AS mean_vi,
     AVG(tachy_proportion) AS mean_tachy_burden,
     AVG(map_proportion) AS mean_map_burden,
     AVG(los) AS mean_los,
     AVG(mortality) AS mortality_rate
  FROM general_per_stay
),

-- Quantiles for the general ICU population
general_quants AS (
  SELECT
     quantiles[OFFSET(25)] AS p25_vi,
     quantiles[OFFSET(50)] AS p50_vi,
     quantiles[OFFSET(75)] AS p75_vi,
     quantiles[OFFSET(90)] AS p90_vi
  FROM (
     SELECT APPROX_QUANTILES(vital_instability_index, 100) AS quantiles
     FROM general_per_stay
  )
)

SELECT
  'target' AS cohort_group,
  ts.mean_vi,
  tq.p25_vi,
  tq.p50_vi,
  tq.p75_vi,
  tq.p90_vi,
  ts.mean_tachy_burden,
  ts.mean_map_burden,
  ts.mean_los,
  ts.mortality_rate
FROM target_summ ts CROSS JOIN target_quants tq

UNION ALL

SELECT
  'general' AS cohort_group,
  gs.mean_vi,
  gq.p25_vi,
  gq.p50_vi,
  gq.p75_vi,
  gq.p90_vi,
  gs.mean_tachy_burden,
  gs.mean_map_burden,
  gs.mean_los,
  gs.mortality_rate
FROM general_summ gs CROSS JOIN general_quants gq;