WITH population AS (
  SELECT 
    ic.stay_id,
    ic.hadm_id,
    ic.intime,
    ic.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON ic.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON ic.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 74 AND 84
),
condition_events AS (
  SELECT 
    pop.stay_id,
    TIMESTAMP_DIFF(ce.charttime, pop.intime, HOUR) AS hour_bucket,
    CASE ce.itemid
      WHEN 223762 THEN 'fever'
      WHEN 220277 THEN 'hypoxemia'
      WHEN 220210 THEN 'tachypnea'
    END AS condition
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN population pop 
    ON ce.stay_id = pop.stay_id
  WHERE ce.charttime >= pop.intime 
    AND ce.charttime < TIMESTAMP_ADD(pop.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND (
      (ce.itemid = 223762 AND ce.valuenum > 38.5) OR
      (ce.itemid = 220277 AND ce.valuenum < 90) OR
      (ce.itemid = 220210 AND ce.valuenum > 20)
    )
),
instability_metrics AS (
  SELECT 
    pop.stay_id,
    pop.hadm_id,
    pop.los,
    pop.hospital_expire_flag,
    COUNT(DISTINCT ce.hour_bucket) AS unstable_hours_total,
    COUNT(DISTINCT CASE WHEN ce.condition = 'fever' THEN ce.hour_bucket END) AS unstable_hours_fever,
    COUNT(DISTINCT CASE WHEN ce.condition = 'hypoxemia' THEN ce.hour_bucket END) AS unstable_hours_hypoxemia,
    COUNT(DISTINCT CASE WHEN ce.condition = 'tachypnea' THEN ce.hour_bucket END) AS unstable_hours_tachypnea
  FROM population pop
  LEFT JOIN condition_events ce 
    ON pop.stay_id = ce.stay_id
  GROUP BY pop.stay_id, pop.hadm_id, pop.los, pop.hospital_expire_flag
),
ranked AS (
  SELECT 
    *,
    NTILE(10) OVER (ORDER BY unstable_hours_total DESC) AS decile
  FROM instability_metrics
),
p90_value AS (
  SELECT 
    APPROX_QUANTILES(unstable_hours_total, 100)[OFFSET(90)] AS p90
  FROM instability_metrics
),
top_decile_summary AS (
  SELECT 
    COUNT(*) AS n,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    AVG(unstable_hours_fever) AS mean_fever_hours,
    AVG(unstable_hours_hypoxemia) AS mean_hypoxemia_hours,
    AVG(unstable_hours_tachypnea) AS mean_tachypnea_hours
  FROM ranked
  WHERE decile = 1
)
SELECT 
  p90_value.p90,
  top_decile_summary.n,
  top_decile_summary.mean_los,
  top_decile_summary.mortality_pct,
  top_decile_summary.mean_fever_hours,
  top_decile_summary.mean_hypoxemia_hours,
  top_decile_summary.mean_tachypnea_hours
FROM p90_value
CROSS JOIN top_decile_summary;