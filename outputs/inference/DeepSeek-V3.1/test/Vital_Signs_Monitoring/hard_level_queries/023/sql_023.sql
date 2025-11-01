WITH cohort AS (
  -- Base cohort: male, age 55-65, ICU patients
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id,
    i.first_careunit,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),

hfnc_patients AS (
  -- Patients who received HFNC within 24h of ICU admission
  SELECT 
    c.*,
    pe.starttime as hfnc_time
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
  WHERE pe.itemid = 226794  -- HFNC itemid
    AND DATETIME_DIFF(pe.starttime, c.intime, HOUR) <= 24
),

controls AS (
  -- Potential controls: no HFNC ever
  SELECT c.*
  FROM cohort c
  WHERE NOT EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    WHERE pe.stay_id = c.stay_id 
    AND pe.itemid = 226794
  )
),

matched_controls AS (
  -- For each HFNC patient, assign a control matched on first_careunit, anchor_age
  SELECT 
    h.subject_id as hfnc_subject_id,
    h.stay_id as hfnc_stay_id,
    c.subject_id as control_subject_id,
    c.stay_id as control_stay_id
  FROM hfnc_patients h
  CROSS JOIN (
    SELECT c.*, ROW_NUMBER() OVER (PARTITION BY first_careunit, anchor_age ORDER BY RAND()) as rn
    FROM controls c
  ) c
  WHERE h.first_careunit = c.first_careunit
    AND h.anchor_age = c.anchor_age
    AND c.rn = 1  -- One control per matching group
),

combined_groups AS (
  -- Combine HFNC and matched controls
  SELECT 
    h.subject_id,
    h.stay_id,
    h.first_careunit,
    h.los,
    h.hospital_expire_flag,
    'HFNC' as group_label
  FROM hfnc_patients h
  UNION ALL
  SELECT 
    c.control_subject_id as subject_id,
    c.control_stay_id as stay_id,
    co.first_careunit,
    co.los,
    co.hospital_expire_flag,
    'Control' as group_label
  FROM matched_controls c
  INNER JOIN controls co
    ON c.control_stay_id = co.stay_id
),

vitals AS (
  -- Calculate tachycardia and hypotension burdens
  SELECT 
    cg.subject_id,
    cg.stay_id,
    cg.group_label,
    -- Tachycardia burden: % of HR > 100
    SAFE_DIVIDE(
      SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END),
      COUNT(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL THEN 1 END)
    ) AS tachycardia_burden,
    -- Hypotension burden: % of systolic BP < 90
    SAFE_DIVIDE(
      SUM(CASE WHEN ce.itemid = 220179 AND ce.valuenum < 90 THEN 1 ELSE 0 END),
      COUNT(CASE WHEN ce.itemid = 220179 AND ce.valuenum IS NOT NULL THEN 1 END)
    ) AS hypotension_burden
  FROM combined_groups cg
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cg.stay_id = ce.stay_id
  WHERE ce.itemid IN (220045, 220179)  -- HR and systolic BP
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude erroneous values
  GROUP BY cg.subject_id, cg.stay_id, cg.group_label
)

-- Final aggregation
SELECT 
  cg.group_label,
  COUNT(*) AS n_patients,
  -- Tachycardia burden percentiles
  APPROX_QUANTILES(v.tachycardia_burden, 100)[50] AS tachycardia_median,
  APPROX_QUANTILES(v.tachycardia_burden, 100)[25] AS tachycardia_p25,
  APPROX_QUANTILES(v.tachycardia_burden, 100)[75] AS tachycardia_p75,
  APPROX_QUANTILES(v.tachycardia_burden, 100)[95] AS tachycardia_p95,
  -- Hypotension burden percentiles
  APPROX_QUANTILES(v.hypotension_burden, 100)[50] AS hypotension_median,
  APPROX_QUANTILES(v.hypotension_burden, 100)[25] AS hypotension_p25,
  APPROX_QUANTILES(v.hypotension_burden, 100)[75] AS hypotension_p75,
  APPROX_QUANTILES(v.hypotension_burden, 100)[95] AS hypotension_p95,
  -- ICU LOS percentiles
  APPROX_QUANTILES(cg.los, 100)[50] AS los_median,
  APPROX_QUANTILES(cg.los, 100)[25] AS los_p25,
  APPROX_QUANTILES(cg.los, 100)[75] AS los_p75,
  APPROX_QUANTILES(cg.los, 100)[95] AS los_p95,
  -- Mortality rate
  SUM(cg.hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM combined_groups cg
LEFT JOIN vitals v
  ON cg.stay_id = v.stay_id
GROUP BY cg.group_label;