WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.anchor_age,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 37 AND 47
),

-- Identify stays with noninvasive ventilation (CPAP/BiPAP)
ventilated_stays AS (
  SELECT DISTINCT
    ce.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) IN ('cpap mask', 'bipap mask', 'non-invasive ventilation')
    AND ce.stay_id IN (SELECT stay_id FROM cohort)
),

-- Extract max diastolic BP per stay
max_dbp_per_stay AS (
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%diastolic blood pressure%'
    AND ce.valuenum IS NOT NULL
    AND ce.stay_id IN (SELECT stay_id FROM ventilated_stays)
  GROUP BY
    ce.stay_id
)

-- Compute 25th percentile of max diastolic BP
SELECT
  PERCENTILE_CONT(max_dbp, 0.25) OVER() AS dbp_25th_percentile
FROM
  max_dbp_per_stay
LIMIT 1;