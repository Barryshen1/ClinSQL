WITH septic_males AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON i.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic
    ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (LOWER(dic.long_title) LIKE '%sepsis%' OR LOWER(dic.long_title) LIKE '%septic%')
),

diagnostic_events AS (
  SELECT 
    sm.stay_id,
    COUNT(ce.charttime) AS chartevent_count,
    COUNT(me.charttime) AS microbiology_count
  FROM septic_males sm
  LEFT JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON sm.stay_id = ce.stay_id
    AND ce.charttime >= sm.intime
    AND ce.charttime < TIMESTAMP_ADD(sm.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.microbiologyevents me
    ON sm.hadm_id = me.hadm_id
    AND me.charttime >= sm.intime
    AND me.charttime < TIMESTAMP_ADD(sm.intime, INTERVAL 24 HOUR)
  GROUP BY sm.stay_id
),

final_metrics AS (
  SELECT 
    sm.stay_id,
    sm.hadm_id,
    sm.hospital_expire_flag,
    sm.los,
    COALESCE(de.chartevent_count, 0) + COALESCE(de.microbiology_count, 0) AS diagnostic_count
  FROM septic_males sm
  LEFT JOIN diagnostic_events de ON sm.stay_id = de.stay_id
)

SELECT 
  STDDEV(diagnostic_count) AS sd_diagnostic_utilization,
  PERCENTILE_CONT(diagnostic_count, 0.75) AS p75_diagnostic_utilization,
  PERCENTILE_CONT(diagnostic_count, 0.95) AS p95_diagnostic_utilization,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS in_hospital_mortality_pct,
  AVG(los) AS average_los,
  COUNT(DISTINCT hadm_id) AS admissions,
  COUNT(*) AS icu_stays
FROM final_metrics;