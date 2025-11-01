WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age AS age,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
    AND icu.hadm_id = adm.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
),
vent_patients AS (
  SELECT DISTINCT c.*
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%vent%'
     OR LOWER(pe.ordercategoryname) LIKE '%vent%'
),
vitals_48h AS (
  SELECT
    vp.stay_id,
    SUM(CASE WHEN di.label LIKE 'Systolic Blood Pressure%' AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS hypo_count,
    SUM(CASE WHEN di.label LIKE 'Systolic Blood Pressure%' THEN 1 ELSE 0 END) AS sbp_count,
    SUM(CASE WHEN di.label LIKE 'Heart Rate%' AND ce.valuenum > 120 THEN 1 ELSE 0 END) AS tachy_count,
    SUM(CASE WHEN di.label LIKE 'Heart Rate%' THEN 1 ELSE 0 END) AS hr_count
  FROM vent_patients vp
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON vp.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN vp.intime AND DATETIME_ADD(vp.intime, INTERVAL 48 HOUR)
  GROUP BY vp.stay_id
),
score_calc AS (
  SELECT
    vp.*,
    SAFE_DIVIDE(v.hypo_count, v.sbp_count) AS hypo_rate,
    SAFE_DIVIDE(v.tachy_count, v.hr_count) AS tachy_rate,
    SAFE_DIVIDE(v.hypo_count, v.sbp_count) + SAFE_DIVIDE(v.tachy_count, v.hr_count) AS composite_score
  FROM vent_patients vp
  JOIN vitals_48h v
    ON vp.stay_id = v.stay_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(90)] AS p90_score,
    APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] AS p75_score
  FROM score_calc
),
top_quartile AS (
  SELECT sc.*
  FROM score_calc sc
  CROSS JOIN percentiles p
  WHERE sc.composite_score >= p.p75_score
),
metrics_top_quartile AS (
  SELECT
    AVG(CASE WHEN hypo_rate > 0 THEN 1 ELSE 0 END) AS prop_hypotension,
    AVG(CASE WHEN tachy_rate > 0 THEN 1 ELSE 0 END) AS prop_tachycardia,
    AVG(los) AS avg_icu_los_days,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
  FROM top_quartile
)
SELECT
  p.p90_score AS score_90th_percentile,
  tq.prop_hypotension,
  tq.prop_tachycardia,
  tq.avg_icu_los_days,
  tq.hospital_mortality_rate
FROM metrics_top_quartile tq
CROSS JOIN percentiles p;