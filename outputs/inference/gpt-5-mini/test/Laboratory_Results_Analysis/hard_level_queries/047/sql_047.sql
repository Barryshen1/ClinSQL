WITH
-- 1) Identify ARDS admissions via diagnosis description
ards_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
   AND diag.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%acute respiratory distress%'
     OR LOWER(d.long_title) LIKE '%ards%'
),

-- 2) Male patients aged 71-81 with ARDS admissions
target_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN ards_hadm ar
    ON a.hadm_id = ar.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),

-- 3) First ICU stay per admission (earliest intime for that hadm_id)
first_icustay AS (
  SELECT ic.subject_id, ic.hadm_id, ic.stay_id, ic.intime, ic.outtime, ic.los
  FROM (
    SELECT icustays.*,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
    WHERE icustays.hadm_id IN (SELECT hadm_id FROM target_admissions)
  ) ic
  WHERE ic.rn = 1
),

-- 4) Abnormal vital events in first 72 hours of the ICU stay (score components)
--  Use d_items.label patterns to identify vitals and apply threshold rules.
abnormal_vitals AS (
  SELECT
    f.hadm_id,
    f.stay_id,
    ce.charttime,
    -- determine which vital this measurement corresponds to (label) and its numeric value
    d.label AS item_label,
    ce.valuenum,
    CASE
      -- Heart rate
      WHEN LOWER(d.label) LIKE '%heart rate%' AND ce.valuenum IS NOT NULL
           AND (ce.valuenum > 120 OR ce.valuenum < 50) THEN 1
      -- Respiratory rate
      WHEN (LOWER(d.label) LIKE '%respiratory rate%' OR LOWER(d.label) LIKE '%resp rate%')
           AND ce.valuenum IS NOT NULL
           AND (ce.valuenum > 30 OR ce.valuenum < 8) THEN 1
      -- SpO2 / oxygen saturation
      WHEN (LOWER(d.label) LIKE '%spo2%' OR LOWER(d.label) LIKE '%oxygen saturation%' OR LOWER(d.label) LIKE '%oxy sat%')
           AND ce.valuenum IS NOT NULL
           AND ce.valuenum < 90 THEN 1
      -- Temperature (assume Celsius; many entries in d_items are C)
      WHEN (LOWER(d.label) LIKE '%temperature%' OR LOWER(d.label) LIKE '%temp%')
           AND ce.valuenum IS NOT NULL
           AND (ce.valuenum > 38.5 OR ce.valuenum < 36) THEN 1
      -- Systolic blood pressure (non-invasive or arterial systolic)
      WHEN (LOWER(d.label) LIKE '%systolic%' OR LOWER(d.label) LIKE '%non invasive blood pressure systolic%' OR LOWER(d.label) LIKE '%arterial bp systolic%')
           AND ce.valuenum IS NOT NULL
           AND ce.valuenum < 90 THEN 1
      -- Mean arterial pressure (MAP)
      WHEN (LOWER(d.label) LIKE '%mean arterial pressure%' OR LOWER(d.label) LIKE '%map%')
           AND ce.valuenum IS NOT NULL
           AND ce.valuenum < 65 THEN 1
      ELSE 0
    END AS is_abnormal
  FROM first_icustay f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.hadm_id = f.hadm_id
   AND ce.stay_id = f.stay_id
   -- only measurements within first 72 hours of ICU intime
   AND ce.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ce.itemid = d.itemid
  -- Only consider numeric values (valuenum) where applicable; filter will be in CASE
),

-- 5) Per-admission instability score = count of abnormal vital measurements in 72h
instability_by_hadm AS (
  SELECT
    hadm_id,
    SUM(is_abnormal) AS instability_score
  FROM abnormal_vitals
  GROUP BY hadm_id
),

-- 6) Some ARDS admissions may have zero abnormal vitals recorded in CHARTEVENTS;
-- include them with score 0 to ensure percentile uses full cohort
all_target_scores AS (
  SELECT ta.hadm_id,
         COALESCE(ib.instability_score, 0) AS instability_score
  FROM target_admissions ta
  LEFT JOIN instability_by_hadm ib
    ON ta.hadm_id = ib.hadm_id
),

-- 7) 90th percentile threshold (approximate)
percentile_90 AS (
  SELECT
    (APPROX_QUANTILES(instability_score, 100))[OFFSET(90)] AS p90_score
  FROM all_target_scores
),

-- 8) High-instability cohort: those at or above the threshold
high_instability_hadms AS (
  SELECT a.hadm_id, a.instability_score
  FROM all_target_scores a
  CROSS JOIN percentile_90 p
  WHERE a.instability_score >= p.p90_score
),

-- 9) Outcomes for high-instability cohort
high_cohort_outcomes AS (
  SELECT
    COUNT(*) AS n_patients,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_hospital_los_days,
    AVG(f.los) AS mean_icu_los_days,
    SUM(a.hospital_expire_flag)/COUNT(*) AS mortality_rate
  FROM high_instability_hadms h
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON h.hadm_id = a.hadm_id
  LEFT JOIN first_icustay f
    ON h.hadm_id = f.hadm_id
),

-- 10) Identify critical lab events within first 72 hours of ICU stay for cohort
critical_labs_cohort AS (
  SELECT DISTINCT l.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN high_instability_hadms h
    ON l.hadm_id = h.hadm_id
  JOIN first_icustay f
    ON l.hadm_id = f.hadm_id
  WHERE l.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
    AND (
      -- numeric outside provided reference range
      (l.valuenum IS NOT NULL AND (
         (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
         OR
         (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
      ))
      -- OR textual flag indicating abnormality/critical
      OR (LOWER(COALESCE(l.flag, '')) LIKE '%abnormal%')
      OR (LOWER(COALESCE(l.flag, '')) LIKE '%critical%')
    )
),

-- 11) Critical-lab rate for high-instability cohort
critical_rate_cohort AS (
  SELECT
    COUNT(DISTINCT cl.hadm_id) AS n_with_critical_lab,
    (COUNT(DISTINCT cl.hadm_id) * 1.0) / NULLIF((SELECT COUNT(*) FROM high_instability_hadms), 0) AS critical_lab_rate
  FROM critical_labs_cohort cl
),

-- 12) For comparison: define general inpatient population (all admissions, adults)
general_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age >= 18
),

-- 13) Critical labs in first 72 hours after hospital admission for general inpatients
critical_labs_general AS (
  SELECT DISTINCT l.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN general_admissions ga
    ON l.hadm_id = ga.hadm_id
  WHERE l.charttime BETWEEN ga.admittime AND TIMESTAMP_ADD(ga.admittime, INTERVAL 72 HOUR)
    AND (
      (l.valuenum IS NOT NULL AND (
         (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
         OR
         (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
      ))
      OR (LOWER(COALESCE(l.flag, '')) LIKE '%abnormal%')
      OR (LOWER(COALESCE(l.flag, '')) LIKE '%critical%')
    )
),

-- 14) Critical-lab rate for general inpatients
critical_rate_general AS (
  SELECT
    COUNT(DISTINCT clg.hadm_id) AS n_with_critical_lab,
    (COUNT(DISTINCT clg.hadm_id) * 1.0) / NULLIF((SELECT COUNT(*) FROM general_admissions), 0) AS critical_lab_rate
  FROM critical_labs_general clg
)

-- Final output: assemble all results
SELECT
  -- the 90th percentile threshold
  p.p90_score AS instability_90th_percentile_score,

  -- counts
  (SELECT COUNT(*) FROM all_target_scores) AS n_target_ards_male_71_81,
  (SELECT COUNT(*) FROM high_instability_hadms) AS n_high_instability,

  -- high-instability cohort outcomes
  hco.n_deaths,
  hco.n_patients,
  hco.mortality_rate,
  hco.mean_hospital_los_days,
  hco.mean_icu_los_days,

  -- critical lab comparisons
  crc.n_with_critical_lab AS n_high_cohort_with_critical_lab,
  crc.critical_lab_rate AS high_cohort_critical_lab_rate,
  crg.n_with_critical_lab AS n_general_with_critical_lab,
  crg.critical_lab_rate AS general_critical_lab_rate

FROM percentile_90 p
CROSS JOIN high_cohort_outcomes hco
CROSS JOIN critical_rate_cohort crc
CROSS JOIN critical_rate_general crg;