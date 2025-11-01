WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.subject_id = adm.subject_id
      AND icu.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),
hfnc_exposed AS (
  -- identify stays with any HFNC input in first 48h
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    cohort.intime
  FROM
    cohort
    JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
      ON cohort.subject_id = ie.subject_id
      AND cohort.hadm_id = ie.hadm_id
      AND cohort.stay_id = ie.stay_id
  WHERE
    ie.ordercategoryname LIKE '%High Flow Nasal Cannula%'
    AND ie.starttime BETWEEN cohort.intime
                         AND TIMESTAMP_ADD(cohort.intime, INTERVAL 48 HOUR)
),
scores AS (
  -- pull the first instability score (itemid=9999) in the first 48h
  SELECT
    ch.subject_id,
    ch.hadm_id,
    ch.stay_id,
    MIN(ch.charttime) AS first_charttime
  FROM
    hfnc_exposed
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ch
      ON hfnc_exposed.subject_id = ch.subject_id
      AND hfnc_exposed.hadm_id = ch.hadm_id
      AND hfnc_exposed.stay_id = ch.stay_id
  WHERE
    ch.itemid = 9999
    AND ch.charttime BETWEEN hfnc_exposed.intime
                        AND TIMESTAMP_ADD(hfnc_exposed.intime, INTERVAL 48 HOUR)
  GROUP BY
    ch.subject_id, ch.hadm_id, ch.stay_id
),
inst_scores AS (
  -- attach the actual score value
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    ce.valuenum AS score
  FROM
    scores AS s
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON s.subject_id = ce.subject_id
      AND s.hadm_id = ce.hadm_id
      AND s.stay_id = ce.stay_id
      AND s.first_charttime = ce.charttime
      AND ce.itemid = 9999
),
percentiles AS (
  -- compute overall percentile of score=85 and 90th percentile
  SELECT
    SAFE_DIVIDE(COUNTIF(score <= 85) * 100.0, COUNT(*)) AS percentile_85,
    APPROX_QUANTILES(score, 100)[OFFSET(90)] AS p90_score
  FROM
    inst_scores
),
top_decile AS (
  -- identify stays in the top decile
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.score
  FROM
    inst_scores AS i
    CROSS JOIN percentiles AS pct
  WHERE
    i.score >= pct.p90_score
)
SELECT
  pct.percentile_85,
  td_stats.avg_icu_los_days,
  td_stats.hosp_mortality_rate
FROM
  percentiles AS pct,
  (
    SELECT
      AVG(co.los) AS avg_icu_los_days,
      AVG(co.hospital_expire_flag) * 100.0 AS hosp_mortality_rate
    FROM
      top_decile AS td
      JOIN cohort AS co
        ON td.subject_id = co.subject_id
        AND td.hadm_id = co.hadm_id
        AND td.stay_id = co.stay_id
  ) AS td_stats;