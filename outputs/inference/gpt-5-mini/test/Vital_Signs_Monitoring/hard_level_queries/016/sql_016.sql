WITH patient_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    p.gender,
    p.anchor_age,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),

transplants AS (
  -- Flag admissions with any diagnosis whose long_title mentions "transplant"
  SELECT DISTINCT hadm_id, 1 AS is_transplant
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%transplant%'
),

-- Extract chart events in first 72 hours and flag instability events
events AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    -- Fever flag: attempt to handle C vs F units; treat missing unit as Celsius threshold
    CASE
      WHEN (
        (LOWER(di.label) LIKE '%temp%' OR LOWER(di.label) LIKE '%temperature%')
        AND c.valuenum IS NOT NULL
        AND (
          (c.valueuom IS NOT NULL AND LOWER(c.valueuom) LIKE '%f' AND ((c.valuenum - 32.0) * 5.0/9.0) > 38.5)
          OR (c.valueuom IS NOT NULL AND LOWER(c.valueuom) LIKE '%c' AND c.valuenum > 38.5)
          OR (c.valueuom IS NULL AND c.valuenum > 38.5)
        )
      ) THEN 1 ELSE 0 END AS fever_flag,
    -- SpO2 flag (percent)
    CASE
      WHEN (
        (LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%' OR LOWER(di.label) LIKE '%oxyhemoglobin%')
        AND c.valuenum IS NOT NULL
        AND c.valuenum < 90
      ) THEN 1 ELSE 0 END AS spo2_flag,
    -- Respiratory rate flag
    CASE
      WHEN (
        (LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%resp rate%' OR LOWER(di.label) LIKE '%respiration rate%')
        AND c.valuenum IS NOT NULL
        AND c.valuenum > 20
      ) THEN 1 ELSE 0 END AS rr_flag
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  JOIN patient_stays ps
    ON c.stay_id = ps.stay_id
  WHERE c.charttime BETWEEN ps.intime AND TIMESTAMP_ADD(ps.intime, INTERVAL 72 HOUR)
    -- Restrict to likely relevant labels to reduce noise
    AND (
      LOWER(di.label) LIKE '%temp%'
      OR LOWER(di.label) LIKE '%temperature%'
      OR LOWER(di.label) LIKE '%spo2%'
      OR LOWER(di.label) LIKE '%oxygen%'
      OR LOWER(di.label) LIKE '%oxyhemoglobin%'
      OR LOWER(di.label) LIKE '%respiratory%'
      OR LOWER(di.label) LIKE '%resp rate%'
    )
),

-- Aggregate per stay to produce composite counts
stay_scores AS (
  SELECT
    e.stay_id,
    e.hadm_id,
    SUM(e.fever_flag) AS n_fever,
    SUM(e.spo2_flag) AS n_spo2,
    SUM(e.rr_flag) AS n_rr,
    SUM(e.fever_flag + e.spo2_flag + e.rr_flag) AS composite_count
  FROM events e
  GROUP BY e.stay_id, e.hadm_id
)

-- Final aggregation: group by Transplant vs Non-Transplant
SELECT
  IF(t.is_transplant = 1, 'Transplant', 'Non-Transplant') AS group_label,
  COUNT(*) AS n_icustays,
  SUM(IF(ps.deathtime IS NOT NULL AND ps.deathtime BETWEEN ps.intime AND ps.outtime, 1, 0)) AS deaths_in_icu,
  SAFE_DIVIDE(SUM(IF(ps.deathtime IS NOT NULL AND ps.deathtime BETWEEN ps.intime AND ps.outtime, 1, 0)), COUNT(*)) AS mortality_rate,
  -- Composite instability score quantiles (approx): p25, median, p75
  APPROX_QUANTILES(COALESCE(ss.composite_count, 0), 4)[OFFSET(1)] AS composite_p25,
  APPROX_QUANTILES(COALESCE(ss.composite_count, 0), 4)[OFFSET(2)] AS composite_median,
  APPROX_QUANTILES(COALESCE(ss.composite_count, 0), 4)[OFFSET(3)] AS composite_p75,
  -- ICU LOS (days) quantiles (approx): p25, median, p75
  APPROX_QUANTILES(ps.los, 4)[OFFSET(1)] AS los_p25_days,
  APPROX_QUANTILES(ps.los, 4)[OFFSET(2)] AS los_median_days,
  APPROX_QUANTILES(ps.los, 4)[OFFSET(3)] AS los_p75_days
FROM patient_stays ps
LEFT JOIN transplants t
  ON ps.hadm_id = t.hadm_id
LEFT JOIN stay_scores ss
  ON ps.stay_id = ss.stay_id
GROUP BY group_label
ORDER BY group_label;