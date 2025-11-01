WITH eligible_population AS (
  -- ICU stays for male patients aged 45-55 with heart failure
  SELECT i.subject_id,
         i.hadm_id,
         i.stay_id,
         i.intime,
         i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id AND a.subject_id = di.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE (p.gender = 'M' OR LOWER(p.gender) = 'male')
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(dic.long_title) LIKE '%heart failure%'
),

hr_obs AS (
  -- Heart rate observations within first 72h
  SELECT ep.stay_id,
         COUNT(*) AS hr_obs,
         SUM(CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_abn
  FROM eligible_population AS ep
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.stay_id = ep.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= ep.intime
    AND ce.charttime < TIMESTAMP_ADD(ep.intime, INTERVAL 72 HOUR)
    AND di.label LIKE '%Heart rate%'
  GROUP BY ep.stay_id
),

map_obs AS (
  -- Mean arterial pressure observations within first 72h
  SELECT ep.stay_id,
         COUNT(*) AS map_obs,
         SUM(CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_abn
  FROM eligible_population AS ep
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.stay_id = ep.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= ep.intime
    AND ce.charttime < TIMESTAMP_ADD(ep.intime, INTERVAL 72 HOUR)
    AND di.label LIKE '%Mean arterial pressure%'
  GROUP BY ep.stay_id
),

rr_obs AS (
  -- Respiratory rate observations within first 72h
  SELECT ep.stay_id,
         COUNT(*) AS rr_obs,
         SUM(CASE WHEN ce.valuenum > 20 THEN 1 ELSE 0 END) AS rr_abn
  FROM eligible_population AS ep
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.stay_id = ep.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= ep.intime
    AND ce.charttime < TIMESTAMP_ADD(ep.intime, INTERVAL 72 HOUR)
    AND di.label LIKE '%Respiratory rate%'
  GROUP BY ep.stay_id
),

per_stay AS (
  SELECT
    ep.stay_id,
    ep.hadm_id,
    ep.subject_id,
    ep.intime,
    ep.los,
    adm.hospital_expire_flag
  FROM eligible_population ep
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ep.hadm_id = adm.hadm_id
),

instability AS (
  SELECT
    ps.stay_id,
    ps.hadm_id,
    ps.subject_id,
    ps.intime,
    ps.los,
    ps.hospital_expire_flag,
    COALESCE(h.hr_obs, 0) AS hr_obs,
    COALESCE(h.hr_abn, 0) AS hr_abn,
    COALESCE(m.map_obs, 0) AS map_obs,
    COALESCE(m.map_abn, 0) AS map_abn,
    COALESCE(r.rr_obs, 0) AS rr_obs,
    COALESCE(r.rr_abn, 0) AS rr_abn,
    (COALESCE(h.hr_abn, 0) + COALESCE(m.map_abn, 0) + COALESCE(r.rr_abn, 0)) AS instability_score
  FROM per_stay ps
  LEFT JOIN hr_obs h  ON h.stay_id = ps.stay_id
  LEFT JOIN map_obs m ON m.stay_id = ps.stay_id
  LEFT JOIN rr_obs r  ON r.stay_id = ps.stay_id
),

percentiles AS (
  -- 99th and 75th percentile of the 72h instability score
  SELECT t.q[OFFSET(99)] AS instability_score_99th_percentile,
         t.q[OFFSET(75)] AS instability_score_75th_percentile
  FROM (SELECT APPROX_QUANTILES(instability_score, 100) AS q FROM instability) AS t
),

enriched AS (
  SELECT
    ins.stay_id,
    ins.hadm_id,
    ins.subject_id,
    ins.intime,
    ins.los,
    ins.hospital_expire_flag,
    ins.instability_score,
    ins.hr_obs,
    ins.hr_abn,
    ins.map_obs,
    ins.map_abn,
    ins.rr_obs,
    ins.rr_abn,
    CASE WHEN ins.hr_obs > 0 THEN CAST(ins.hr_abn AS FLOAT64) / ins.hr_obs END AS hr_prop,
    CASE WHEN ins.map_obs > 0 THEN CAST(ins.map_abn AS FLOAT64) / ins.map_obs END AS map_prop,
    CASE WHEN ins.rr_obs > 0 THEN CAST(ins.rr_abn AS FLOAT64) / ins.rr_obs END AS rr_prop,
    ps_pct.instability_score_99th_percentile,
    ps_pct.instability_score_75th_percentile,
    CASE WHEN ins.instability_score >= ps_pct.instability_score_75th_percentile THEN 1 ELSE 0 END AS is_top_quartile
  FROM instability AS ins
  CROSS JOIN percentiles AS ps_pct
)

SELECT
  instability_score_99th_percentile,
  instability_score_75th_percentile,
  AVG(hr_prop) FILTER(WHERE is_top_quartile = 1) AS top_hr_prop_avg,
  AVG(map_prop) FILTER(WHERE is_top_quartile = 1) AS top_map_prop_avg,
  AVG(rr_prop) FILTER(WHERE is_top_quartile = 1) AS top_rr_prop_avg,
  AVG(los) FILTER(WHERE is_top_quartile = 1) AS top_los_avg,
  AVG(hospital_expire_flag) FILTER(WHERE is_top_quartile = 1) AS top_mortality_rate,
  AVG(hr_prop) AS overall_hr_prop_avg,
  AVG(map_prop) AS overall_map_prop_avg,
  AVG(rr_prop) AS overall_rr_prop_avg,
  AVG(los) AS overall_los_avg,
  AVG(hospital_expire_flag) AS overall_mortality_rate
FROM enriched;