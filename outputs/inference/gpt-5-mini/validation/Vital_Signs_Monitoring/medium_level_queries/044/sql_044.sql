WITH systolic_items AS (
  -- identify itemids that look like systolic blood pressure measurements
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    -- prefer mmHg units when present, but allow if unitname is NULL/absent
    AND (unitname IS NULL OR LOWER(unitname) LIKE '%mmhg%')
),
sbp_measurements AS (
  -- systolic BP measurements occurring during the first 48 hours of the ICU stay
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN systolic_items di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
   AND ce.subject_id = icu.subject_id
  WHERE ce.valuenum IS NOT NULL
    -- plausible physiologic filter for systolic BP
    AND ce.valuenum BETWEEN 20 AND 300
    -- restrict to first 48 hours of the ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
),
per_stay_avg AS (
  -- per-ICU-stay average systolic BP within first 48 hours
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(valuenum) AS avg_sbp
  FROM sbp_measurements
  GROUP BY stay_id, subject_id, hadm_id
),
eligible_stays AS (
  -- filter to male patients aged 81-91 (anchor_age from HOSP.patients)
  SELECT
    psa.stay_id,
    psa.subject_id,
    psa.hadm_id,
    psa.avg_sbp
  FROM per_stay_avg psa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON psa.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
)
SELECT
  COUNT(*) AS n_stays,
  SUM(CASE WHEN avg_sbp <= 150 THEN 1 ELSE 0 END) AS n_leq_150,
  SAFE_MULTIPLY(
    SAFE_DIVIDE(SUM(CASE WHEN avg_sbp <= 150 THEN 1 ELSE 0 END), COUNT(*)),
    100
  ) AS percentile_of_150
FROM eligible_stays;