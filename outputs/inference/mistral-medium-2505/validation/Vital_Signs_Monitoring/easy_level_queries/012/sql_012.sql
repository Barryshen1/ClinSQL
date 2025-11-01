WITH
-- Get male patients aged 49-59
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
),

-- Get step-down/IMC stays
stepdown_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.transfers` t
  ON
    s.subject_id = t.subject_id
    AND s.hadm_id = t.hadm_id
  WHERE
    t.careunit IN ('Stepdown', 'IMC')
    AND s.subject_id IN (SELECT subject_id FROM male_patients)
),

-- Get diastolic BP measurements (itemid 220050)
diastolic_bp AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS diastolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    ce.itemid = 220050  -- NBP Diastolic
    AND ce.valuenum IS NOT NULL
    AND ce.subject_id IN (SELECT subject_id FROM male_patients)
),

-- Calculate mean diastolic BP per stay
mean_bp_per_stay AS (
  SELECT
    d.stay_id,
    AVG(d.diastolic_bp) AS mean_diastolic_bp
  FROM
    diastolic_bp d
  JOIN
    stepdown_stays s
  ON
    d.subject_id = s.subject_id
    AND d.hadm_id = s.hadm_id
    AND d.stay_id = s.stay_id
  GROUP BY
    d.stay_id
)

-- Calculate IQR of mean diastolic BP per stay
SELECT
  PERCENTILE_CONT(mean_diastolic_bp, 0.25) OVER() AS percentile_25,
  PERCENTILE_CONT(mean_diastolic_bp, 0.75) OVER() AS percentile_75,
  PERCENTILE_CONT(mean_diastolic_bp, 0.75) OVER() - PERCENTILE_CONT(mean_diastolic_bp, 0.25) OVER() AS iqr
FROM
  mean_bp_per_stay
LIMIT 1;