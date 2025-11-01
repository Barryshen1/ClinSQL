WITH eligible_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'Male'
    AND pat.anchor_age BETWEEN 78 AND 88
),

-- 2) Identify HHS cases via ICD long titles (hyperosmolar / hyperosmolarity)
hhs_cases AS (
  SELECT DISTINCT e.subject_id, e.hadm_id, e.stay_id
  FROM eligible_stays AS e
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di ON
       di.subject_id = e.subject_id AND di.hadm_id = e.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi ON
       ddi.icd_code = di.icd_code AND ddi.icd_version = di.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%hyperosmolar%'
     OR LOWER(ddi.long_title) LIKE '%hyperosmolarity%'
),

-- 3) Mark each stay as HHS (1) or Control (0)
stays AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    e.intime,
    e.outtime,
    CASE WHEN h.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_hhs
  FROM eligible_stays AS e
  LEFT JOIN hhs_cases AS h
    ON e.subject_id = h.subject_id
   AND e.hadm_id = h.hadm_id
   AND e.stay_id = h.stay_id
),

-- 4) Compose a per-stay vitals-derived metrics within the first 48 hours
-- 4a. Gather vitals events in the first 48 hours and compute abnormal flags per row
vitals AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.outtime,
    s.is_hhs,
    -- compute abnormal factors per row for each vital sign
    SUM(
      (CASE
         -- Heart rate
         WHEN LOWER(di.label) LIKE '%heart rate%' AND ce.valuenum IS NOT NULL
              AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1 ELSE 0 END)
      +
      (CASE
         -- Respiratory rate
         WHEN LOWER(di.label) LIKE '%respiratory rate%' AND ce.valuenum IS NOT NULL
              AND (ce.valuenum < 12 OR ce.valuenum > 20) THEN 1 ELSE 0 END)
      +
      (CASE
         -- Oxygen saturation
         WHEN LOWER(di.label) LIKE '%oxygen saturation%' AND ce.valuenum IS NOT NULL
              AND ce.valuenum < 92 THEN 1 ELSE 0 END)
      +
      (CASE
         -- Systolic BP
         WHEN LOWER(di.label) LIKE '%systolic%' AND ce.valuenum IS NOT NULL
              AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1 ELSE 0 END)
      +
      (CASE
         -- Mean arterial pressure
         WHEN LOWER(di.label) LIKE '%mean arterial pressure%' AND ce.valuenum IS NOT NULL
              AND (ce.valuenum < 65 OR ce.valuenum > 110) THEN 1 ELSE 0 END)
      +
      (CASE
         -- Temperature
         WHEN LOWER(di.label) LIKE '%temperature%' AND ce.valuenum IS NOT NULL
              AND (ce.valuenum < 36 OR ce.valuenum > 38) THEN 1 ELSE 0 END)
    ) AS instability_score,          -- total abnormal flags across vitals for this row
    SUM(
      (CASE
         WHEN LOWER(di.label) LIKE '%heart rate%' AND ce.valuenum IS NOT NULL
              AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1 ELSE 0 END)
    ) AS abnormal_events               -- count of abnormal heart-rate observations (as a proxy burden)
  FROM stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = s.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ce.itemid
  WHERE ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY
    s.stay_id, s.subject_id, s.hadm_id, s.intime, s.outtime, s.is_hhs
),

-- Include intime in stay_los output to support mort_48h calculations downstream
stay_los AS (
  SELECT
    v.stay_id,
    v.subject_id,
    v.hadm_id,
    v.is_hhs,
    v.instability_score,
    v.abnormal_events,
    s.intime,
    LEAST(TIMESTAMP_DIFF(s.outtime, s.intime, SECOND), 48 * 3600) / 3600.0 AS icu_48h_los_hours
  FROM vitals v
  JOIN stays s
    ON v.stay_id = s.stay_id
),

-- 4c. Mortality within 48 hours: death within 48 hours after ICU intime
mortality AS (
  SELECT
    l.*,
    CASE
      WHEN adm.deathtime IS NOT NULL
       AND TIMESTAMP_DIFF(adm.deathtime, l.intime, SECOND) <= 48 * 3600
      THEN 1 ELSE 0 END AS mort_48h
  FROM stay_los l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON adm.hadm_id = l.hadm_id
),

-- 5) Aggregate to group-level metrics
group_metrics AS (
  SELECT
    CASE WHEN m.is_hhs = 1 THEN 'HHS' ELSE 'Control' END AS group_label,
    m.instability_score,
    m.abnormal_events,
    m.icu_48h_los_hours,
    m.mort_48h
  FROM mortality m
)

-- 6) Compute quartiles for instability score, and means for other metrics by group
SELECT
  gm.group_label,
  -- instability score quartiles (25th, median, 75th)
  CAST((SELECT quant[OFFSET(1)]
        FROM UNNEST(APPROX_QUANTILES(gm.instability_score, 4)) AS quant) AS FLOAT64) AS instability_p25,
  CAST((SELECT quant[OFFSET(2)]
        FROM UNNEST(APPROX_QUANTILES(gm.instability_score, 4)) AS quant) AS FLOAT64) AS instability_median,
  CAST((SELECT quant[OFFSET(3)]
        FROM UNNEST(APPROX_QUANTILES(gm.instability_score, 4)) AS quant) AS FLOAT64) AS instability_p75,
  -- mean abnormal-vital burden
  AVG(gm.abnormal_events) AS mean_abnormal_vital_burden,
  -- mean ICU LOS within first 48 hours
  AVG(gm.icu_48h_los_hours) AS mean_icu_los_hours,
  -- mortality rate within 48 hours
  AVG(gm.mort_48h) AS mortality_rate
FROM group_metrics gm
GROUP BY gm.group_label
ORDER BY gm.group_label;