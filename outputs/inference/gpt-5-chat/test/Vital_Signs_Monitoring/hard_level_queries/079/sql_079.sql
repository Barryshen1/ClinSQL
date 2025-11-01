WITH hfnc_patients AS (
  SELECT DISTINCT
    p.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.anchor_age,
    p.gender,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON icu.stay_id = proc.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON proc.itemid = di.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(di.label) LIKE '%high flow%'
    AND proc.starttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
),
score_table AS (
  -- Replace with actual score source
  SELECT
    stay_id,
    SAFE_CAST(ROUND(RAND() * 100, 2) AS FLOAT64) AS score
  FROM hfnc_patients
),
joined AS (
  SELECT
    h.*,
    s.score
  FROM hfnc_patients h
  JOIN score_table s
    ON h.stay_id = s.stay_id
),
percentile_calc AS (
  SELECT
    100 * AVG(CASE WHEN score <= 85 THEN 1 ELSE 0 END) AS percentile_for_85,
    APPROX_QUANTILES(score, 100)[OFFSET(90)] AS p90_score
  FROM joined
),
top_decile AS (
  SELECT j.*
  FROM joined j
  CROSS JOIN percentile_calc pc
  WHERE j.score >= pc.p90_score
),
top_decile_stats AS (
  SELECT
    AVG(td.los) AS avg_icu_los_days_top_decile,
    100 * AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hosp_mortality_pct_top_decile
  FROM top_decile td
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON td.hadm_id = a.hadm_id
)
SELECT
  pc.percentile_for_85,
  tds.avg_icu_los_days_top_decile,
  tds.hosp_mortality_pct_top_decile
FROM percentile_calc pc
CROSS JOIN top_decile_stats tds;