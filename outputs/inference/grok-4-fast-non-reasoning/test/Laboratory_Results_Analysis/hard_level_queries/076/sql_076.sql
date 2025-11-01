WITH cohort AS (
  -- Elderly male cohort: first admission per patient
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.hadm_id IS NOT NULL  -- Ensure valid admission
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

general_cohort AS (
  -- General adult inpatients: first admission per patient
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age >= 18
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.hadm_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

critical_items AS (
  -- Common critical lab itemids (e.g., electrolytes, renal, CBC; selected for ACS/elderly instability)
  SELECT itemid
  FROM UNNEST([
    225655,  -- Sodium
    227442,  -- Potassium
    50971,   -- Magnesium
    50912,   -- Calcium
    50893,   -- Chloride
    51006,   -- Bicarbonate
    51222,   -- Creatinine
    51265,   -- BUN
    51237,   -- Glucose
    50809,   -- WBC
    51279,   -- Platelets
    51301,   -- PT
    51275,   -- INR
    50811,   -- Hemoglobin
    51221,   -- Albumin
    50862,   -- AST
    50863,   -- ALT
    50878,   -- Total Bilirubin
    50970,   -- Lactate
    51202    -- Troponin
  ]) AS itemid
),

lab_scores AS (
  -- Compute instability score: count of critical lab events in first 72h per admission
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNTIF(
      le.valuenum IS NOT NULL
      AND le.itemid IN (SELECT itemid FROM critical_items)
      AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        OR le.flag IN ('H', 'L', 'HH', 'LL')
      )
    ) AS instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND c.hadm_id = le.hadm_id
    AND le.charttime >= c.admittime
    AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 3 DAY)
  GROUP BY c.subject_id, c.hadm_id
),

general_lab_scores AS (
  -- Same scoring for general cohort
  SELECT 
    gc.subject_id,
    gc.hadm_id,
    COUNTIF(
      le.valuenum IS NOT NULL
      AND le.itemid IN (SELECT itemid FROM critical_items)
      AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        OR le.flag IN ('H', 'L', 'HH', 'LL')
      )
    ) AS instability_score
  FROM general_cohort gc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON gc.subject_id = le.subject_id
    AND gc.hadm_id = le.hadm_id
    AND le.charttime >= gc.admittime
    AND le.charttime <= TIMESTAMP_ADD(gc.admittime, INTERVAL 3 DAY)
  GROUP BY gc.subject_id, gc.hadm_id
),

scored_cohort AS (
  SELECT 
    ls.*,
    c.los,
    c.hospital_expire_flag,
    c.admittime
  FROM lab_scores ls
  INNER JOIN cohort c ON ls.subject_id = c.subject_id AND ls.hadm_id = c.hadm_id
),

p95_threshold AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.95) OVER (ORDER BY instability_score) AS p95_score
  FROM scored_cohort
),

p95_subgroup AS (
  SELECT 
    sc.*,
    pt.p95_score
  FROM scored_cohort sc
  CROSS JOIN p95_threshold pt
  WHERE sc.instability_score >= pt.p95_score
),

p95_aggregates AS (
  SELECT 
    AVG(los) AS mean_los_days_p95,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct_p95,
    AVG(instability_score) AS avg_critical_events_per_patient_p95
  FROM p95_subgroup
),

general_aggregates AS (
  SELECT 
    AVG(instability_score) AS avg_critical_events_general_inpatients
  FROM general_lab_scores
)

-- Main results
SELECT 
  'Elderly Male Cohort (87-97)' AS cohort_type,
  pt.p95_score AS p95_instability_score,
  pa.mean_los_days_p95,
  pa.mortality_pct_p95,
  pa.avg_critical_events_per_patient_p95,
  ga.avg_critical_events_general_inpatients
FROM p95_threshold pt
CROSS JOIN p95_aggregates pa
CROSS JOIN general_aggregates ga;