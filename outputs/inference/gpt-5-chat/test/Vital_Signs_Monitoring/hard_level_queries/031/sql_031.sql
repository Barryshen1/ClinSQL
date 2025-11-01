WITH postop_icu AS (
  SELECT DISTINCT
    p.subject_id,
    adm.hadm_id,
    icu.stay_id,
    p.gender,
    p.anchor_age,
    adm.hospital_expire_flag,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON adm.hadm_id = proc.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),
abnormal_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    SUM(CASE WHEN ce.itemid IN (223762, 223761) AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_count,
    SUM(CASE WHEN ce.itemid IN (220277, 646) AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_low_count,
    SUM(CASE WHEN ce.itemid IN (220210, 615) AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS rr_high_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (223762, 223761, 220277, 646, 220210, 615)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),
instability AS (
  SELECT
    pi.*,
    ae.fever_count,
    ae.spo2_low_count,
    ae.rr_high_count,
    (ae.fever_count + ae.spo2_low_count + ae.rr_high_count) AS instability_score
  FROM postop_icu pi
  LEFT JOIN abnormal_events ae
    ON pi.subject_id = ae.subject_id
    AND pi.hadm_id = ae.hadm_id
    AND pi.stay_id = ae.stay_id
),
quartiles AS (
  SELECT
    *,
    PERCENTILE_CONT(instability_score, 0.75) OVER() AS p75_score
  FROM instability
),
grouped AS (
  SELECT
    *,
    CASE WHEN instability_score >= p75_score THEN 'top_quartile' ELSE 'other' END AS group_flag
  FROM quartiles
)
SELECT
  group_flag,
  COUNT(*) AS n_stays,
  APPROX_QUANTILES(instability_score, 20)[OFFSET(19)] AS p95_instability_score,
  AVG(fever_count) AS avg_fever_episodes,
  AVG(spo2_low_count) AS avg_spo2_low_episodes,
  AVG(rr_high_count) AS avg_rr_high_episodes,
  AVG(los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM grouped
GROUP BY group_flag
ORDER BY group_flag;