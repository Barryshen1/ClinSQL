WITH
-- 1) Base: female patients aged 43-53 at admission and ICU stays
base_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT64) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT64) BETWEEN 43 AND 53
),

-- 2) ARF filter: keep only stays with Acute Respiratory Failure
arf_cohort AS (
  SELECT bc.subject_id, bc.hadm_id, bc.stay_id, bc.intime
  FROM base_cohort AS bc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON bc.subject_id = diag.subject_id AND bc.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON diag.icd_code = dic.icd_code AND diag.icd_version = dic.icd_version
  WHERE LOWER(dic.long_title) LIKE '%acute respiratory failure%'
),

-- 3) Vital-instability index (VSI) per ICU stay in first 48 hours
vsi_per_stay AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    a.intime,
    SAFE_DIVIDE(SUM(
      CASE
        WHEN LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%' THEN
          CASE WHEN ce.valuenum IS NULL THEN 0
               WHEN ce.valuenum < 60 OR ce.valuenum > 100 THEN 1
               ELSE 0
          END
        WHEN LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%' THEN
          CASE WHEN ce.valuenum IS NULL THEN 0
               WHEN ce.valuenum < 65 THEN 1
               ELSE 0
          END
        WHEN LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%rr%' THEN
          CASE WHEN ce.valuenum IS NULL THEN 0
               WHEN ce.valuenum > 20 OR ce.valuenum < 12 THEN 1
               ELSE 0
          END
        WHEN LOWER(di.label) LIKE '%temperature%' OR LOWER(di.label) LIKE '%temp%' THEN
          CASE WHEN ce.valuenum IS NULL THEN 0
               WHEN ce.valuenum < 36 OR ce.valuenum > 38 THEN 1
               ELSE 0
          END
        ELSE 0
      END
    ), COUNT(*) ) AS vsi
  FROM arf_cohort AS a
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = a.subject_id
   AND ce.hadm_id = a.hadm_id
   AND ce.stay_id = a.stay_id
   AND ce.charttime BETWEEN a.intime AND TIMESTAMP_ADD(a.intime, INTERVAL 48 HOUR)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  GROUP BY a.subject_id, a.hadm_id, a.stay_id, a.intime
),

-- 4) Percentile thresholds
vsi_75 AS (
  SELECT quantiles[OFFSET(75)] AS vsi_75th
  FROM (
    SELECT APPROX_QUANTILES(vsi, 100) AS quantiles
    FROM vsi_per_stay
    WHERE vsi IS NOT NULL
  ) t
),
vsi_95 AS (
  SELECT quantiles[OFFSET(95)] AS vsi_95th
  FROM (
    SELECT APPROX_QUANTILES(vsi, 100) AS quantiles
    FROM vsi_per_stay
    WHERE vsi IS NOT NULL
  ) t
),

-- 5) Stays-by-stats: per-stay summary (MAP<65 hypotension, HR>100 tachycardia, LOS, mortality, VSI)
hypotension_per_stay AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id, COUNT(*) AS hypo_cnt
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%')
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),
tachycardia_per_stay AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id, COUNT(*) AS tachy_cnt
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%')
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),
los_and_mortality AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.los AS icu_los_days, a.hospital_expire_flag AS died_in_hospital
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),
per_stay AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    COALESCE(hp.hypo_cnt, 0) AS hypo_cnt,
    COALESCE(tc.tachy_cnt, 0) AS tachy_cnt,
    lm.icu_los_days AS icu_los_days,
    lm.died_in_hospital,
    v.vsi
  FROM arf_cohort AS s
  LEFT JOIN vsi_per_stay AS v
    ON s.subject_id = v.subject_id AND s.hadm_id = v.hadm_id AND s.stay_id = v.stay_id
  LEFT JOIN hypotension_per_stay AS hp
    ON s.subject_id = hp.subject_id AND s.hadm_id = hp.hadm_id AND s.stay_id = hp.stay_id
  LEFT JOIN tachycardia_per_stay AS tc
    ON s.subject_id = tc.subject_id AND s.hadm_id = tc.hadm_id AND s.stay_id = tc.stay_id
  LEFT JOIN los_and_mortality AS lm
    ON s.subject_id = lm.subject_id AND s.hadm_id = lm.hadm_id AND s.stay_id = lm.stay_id
)

-- 6) Final outputs:
-- a) 95th percentile VSI (first 48 hours)
-- b) All ARF females 43-53 (general ICU population) metrics
-- c) Top VSI quartile subset metrics
SELECT
  '95th percentile VSI (first 48 hours)' AS group_label,
  CAST(vsi_95.vsi_95th AS FLOAT64) AS vsi_95th,
  NULL AS mean_hypotension_cnt,
  NULL AS mean_tachycardia_cnt,
  NULL AS mean_icu_los_days,
  NULL AS mortality_rate
FROM vsi_95
UNION ALL
SELECT
  'All ARF females 43-53 (general ICU population)' AS group_label,
  NULL,
  AVG(p.hypo_cnt) AS mean_hypotension_cnt,
  AVG(p.tachy_cnt) AS mean_tachycardia_cnt,
  AVG(p.icu_los_days) AS mean_icu_los_days,
  AVG(CASE WHEN p.died_in_hospital = 1 THEN 1.0 ELSE 0.0 END) AS mortality_rate
FROM per_stay AS p
UNION ALL
SELECT
  'Top VSI quartile (within ARF females 43-53 ICU)' AS group_label,
  NULL,
  AVG(p.hypo_cnt) AS mean_hypotension_cnt,
  AVG(p.tachy_cnt) AS mean_tachycardia_cnt,
  AVG(p.icu_los_days) AS mean_icu_los_days,
  AVG(CASE WHEN p.died_in_hospital = 1 THEN 1.0 ELSE 0.0 END) AS mortality_rate
FROM per_stay AS p
WHERE p.vsi >= (SELECT vsi_75th FROM vsi_75);