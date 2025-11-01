WITH icu_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 55 AND 65
),
-- identify HFNC itemids from d_items
hfnc_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%high flow%' AND LOWER(label) LIKE '%nasal%'
),
-- exposures = HFNC within first 24h
hfnc_exposure AS (
  SELECT DISTINCT pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN hfnc_items di ON pe.itemid = di.itemid
  JOIN icu_cohort icu ON pe.stay_id = icu.stay_id
  WHERE pe.starttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
),
cohort_flagged AS (
  SELECT c.*,
    CASE WHEN e.stay_id IS NOT NULL THEN 1 ELSE 0 END AS hfnc_24h
  FROM icu_cohort c
  LEFT JOIN hfnc_exposure e
    ON c.stay_id = e.stay_id
),
-- instability score values
instability AS (
  SELECT
    cf.stay_id,
    ce.valuenum
  FROM cohort_flagged cf
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cf.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) = 'instability score'
    AND ce.valuenum IS NOT NULL
),
instability_stats AS (
  SELECT
    cf.hfnc_24h,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(95)] AS p95
  FROM instability i
  JOIN cohort_flagged cf ON i.stay_id = cf.stay_id
  GROUP BY cf.hfnc_24h
),
-- tachycardia burden (HR > 100)
hr AS (
  SELECT
    cf.stay_id,
    ce.valuenum,
    CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END AS tachy_flag
  FROM cohort_flagged cf
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cf.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) = 'heart rate'
    AND ce.valuenum IS NOT NULL
),
tachy_burden AS (
  SELECT
    cf.hfnc_24h,
    AVG(tachy_flag) AS tachy_burden
  FROM hr
  JOIN cohort_flagged cf ON hr.stay_id = cf.stay_id
  GROUP BY cf.hfnc_24h
),
-- hypotension burden (SBP < 90)
sbp AS (
  SELECT
    cf.stay_id,
    ce.valuenum,
    CASE WHEN ce.valuenum < 90 THEN 1 ELSE 0 END AS hypo_flag
  FROM cohort_flagged cf
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cf.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE 'systolic blood pressure%'
    AND ce.valuenum IS NOT NULL
),
hypo_burden AS (
  SELECT
    cf.hfnc_24h,
    AVG(hypo_flag) AS hypo_burden
  FROM sbp
  JOIN cohort_flagged cf ON sbp.stay_id = cf.stay_id
  GROUP BY cf.hfnc_24h
),
-- LOS and mortality
los_mort AS (
  SELECT
    hfnc_24h,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate
  FROM cohort_flagged
  GROUP BY hfnc_24h
)
SELECT
  s.hfnc_24h,
  s.p50 AS instability_median,
  s.p25 AS instability_p25,
  s.p75 AS instability_p75,
  s.p95 AS instability_p95,
  t.tachy_burden,
  h.hypo_burden,
  l.median_los,
  l.mortality_rate
FROM instability_stats s
JOIN tachy_burden t ON s.hfnc_24h = t.hfnc_24h
JOIN hypo_burden h ON s.hfnc_24h = h.hfnc_24h
JOIN los_mort l ON s.hfnc_24h = l.hfnc_24h
ORDER BY hfnc_24h DESC;