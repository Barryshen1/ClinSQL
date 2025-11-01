WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 66 AND 76
),
ventilated_icustays AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN male_patients AS mp
    ON icu.subject_id = mp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON icu.subject_id = pe.subject_id
    AND icu.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON pe.itemid = di.itemid
  -- Filter invasive ventilation procedures
  WHERE di.category LIKE '%Ventilation%'
    AND LOWER(di.label) LIKE '%invasive%'
),
systolic_bp_events AS (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  INNER JOIN ventilated_icustays AS vi
    ON ce.subject_id = vi.subject_id
    AND ce.stay_id = vi.stay_id
  WHERE di.label LIKE 'Systolic%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 300
    AND ce.charttime BETWEEN vi.intime AND TIMESTAMP_ADD(vi.intime, INTERVAL 6 HOUR)
)
SELECT
  quantiles[3] - quantiles[1] AS systolic_bp_iqr
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM systolic_bp_events
);