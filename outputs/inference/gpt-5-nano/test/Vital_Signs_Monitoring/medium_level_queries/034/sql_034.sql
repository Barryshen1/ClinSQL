WITH NIV_ITEMS AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items` di
  WHERE LOWER(di.label) LIKE '%noninvasive%'        -- noninvasive ventilation
     OR LOWER(di.label) LIKE '%cpap%'                -- CPAP
     OR LOWER(di.label) LIKE '%bipap%'               -- BiPAP
),
NIV_STAYS AS (
  SELECT DISTINCT ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  WHERE ie.itemid IN (SELECT itemid FROM NIV_ITEMS)
),
DIASTOLIC_ITEMS AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic%'
),
DIAS_BP AS (
  SELECT
    i.subject_id,
    i.stay_id,
    MAX(ce.valuenum) AS max_diastolic
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND i.outtime
    AND ce.itemid IN (SELECT itemid FROM DIASTOLIC_ITEMS)
    AND i.stay_id IN (SELECT stay_id FROM NIV_STAYS)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
  GROUP BY i.subject_id, i.stay_id
)
SELECT
  -- 25th percentile of the per-stay maximum diastolic BP
  APPROX_QUANTILES(max_diastolic, 100)[OFFSET(24)] AS p25_max_diastolic
FROM DIAS_BP;