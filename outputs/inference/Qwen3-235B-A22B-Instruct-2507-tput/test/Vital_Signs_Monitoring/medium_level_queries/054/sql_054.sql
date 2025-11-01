WITH avg_sbp AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_sbp_24h
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND LOWER(di.label) = 'systolic blood pressure'
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
aged_cohort AS (
  SELECT
    avg_sbp.stay_id,
    avg_sbp.avg_sbp_24h,
    -- Calculate age at ICU admission
    DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_at_admit
  FROM avg_sbp
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON avg_sbp.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 87 AND 97
)
SELECT
  (COUNTIF(avg_sbp_24h <= 150) * 100.0 / COUNT(*)) AS percentile
FROM aged_cohort;