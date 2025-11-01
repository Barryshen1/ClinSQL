WITH male_icu AS (
  -- ICU stays for male patients aged 66-76 (anchor_age used for age filtering)
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
),
vent_stays AS (
  -- Keep stays with evidence of invasive ventilation (text-based search in item label or value)
  SELECT DISTINCT s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime
  FROM male_icu s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = s.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN s.intime AND s.outtime
    AND (
      LOWER(COALESCE(di.label, '')) LIKE '%ventilat%'         -- ventilator / ventilation
      OR LOWER(COALESCE(di.label, '')) LIKE '%endotracheal%'  -- endotracheal tube
      OR LOWER(COALESCE(di.label, '')) LIKE '%intubat%'       -- intubation / intubated
      OR LOWER(COALESCE(ce.value, '')) LIKE '%ventilat%'
      OR LOWER(COALESCE(ce.value, '')) LIKE '%intubat%'
    )
),
systolic_measurements AS (
  -- Systolic BP measurements within first 6 hours of the ICU stay for the ventilated male cohort
  SELECT
    ce2.stay_id,
    ce2.charttime,
    ce2.valuenum AS sbp
  FROM vent_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce2
    ON ce2.stay_id = s.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di2
    ON ce2.itemid = di2.itemid
  WHERE ce2.valuenum IS NOT NULL
    AND ce2.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 6 HOUR)
    AND (
      LOWER(COALESCE(di2.label, '')) LIKE '%systolic%'
      OR LOWER(COALESCE(di2.label, '')) LIKE '%sbp%'
      OR LOWER(COALESCE(di2.label, '')) LIKE '%systolic blood pressure%'
    )
)
-- Compute quantiles (single row) and count (single row), then combine
SELECT
  q.quantiles[OFFSET(1)] AS q1_sbp,
  q.quantiles[OFFSET(3)] AS q3_sbp,
  q.quantiles[OFFSET(3)] - q.quantiles[OFFSET(1)] AS iqr_sbp,
  n.n_measurements
FROM (
  SELECT APPROX_QUANTILES(sbp, 4) AS quantiles
  FROM systolic_measurements
) q
CROSS JOIN (
  SELECT COUNT(*) AS n_measurements
  FROM systolic_measurements
) n;