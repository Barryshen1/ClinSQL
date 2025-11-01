WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Flag ICU stay
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 62 AND 72
),

-- Filter admissions with lower GI bleed
gib_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%gastrointestinal bleed, lower%'
     OR LOWER(d.long_title) LIKE '%lower gastrointestinal hemorrhage%'
     OR LOWER(d.long_title) LIKE '%lower gi bleed%'
),

-- Identify non-invasive diagnostic itemids
diagnostic_items AS (
  SELECT DISTINCT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) IN (
    'ecg', 'eeg', 'pft', 'ct', 'mri', 'x-ray', 'echo', 'ultrasound',
    'electrocardiogram', 'electroencephalogram', 'pulmonary function', 'angiogram'
  )
     OR LOWER(category) IN (
    'ecg', 'eeg', 'pft', 'imaging', 'echo', 'ultrasound', 'diagnostic imaging'
  )
),

-- Count diagnostic events per admission
diagnostic_counts AS (
  SELECT
    ce.hadm_id,
    COUNT(*) AS diag_event_count
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN diagnostic_items di
    ON ce.itemid = di.itemid
  INNER JOIN gib_admissions ga
    ON ce.hadm_id = ga.hadm_id
  WHERE ce.charttime BETWEEN ga.admittime AND COALESCE(ga.dischtime, ce.charttime)
  GROUP BY ce.hadm_id
),

-- Combine with admission info and categorize
admission_summary AS (
  SELECT
    ga.hadm_id,
    ga.los_days,
    ga.had_icu,
    COALESCE(dc.diag_event_count, 0) AS diag_count,
    -- Categorize LOS
    CASE
      WHEN ga.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN ga.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group
  FROM gib_admissions ga
  LEFT JOIN diagnostic_counts dc
    ON ga.hadm_id = dc.hadm_id
  WHERE ga.los_days BETWEEN 1 AND 7
)

-- Final aggregation: mean number of diagnostics per admission by group
SELECT
  los_group,
  had_icu,
  AVG(diag_count) AS mean_diagnostics_per_admission,
  COUNT(*) AS admission_count
FROM admission_summary
WHERE los_group IS NOT NULL
GROUP BY los_group, had_icu
ORDER BY los_group, had_icu;