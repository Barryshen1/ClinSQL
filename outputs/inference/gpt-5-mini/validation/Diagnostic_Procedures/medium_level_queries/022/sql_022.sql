WITH
-- Female patients aged 74
pat_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_age = 74
    AND gender = 'F'
),

-- Admissions for those patients with LOS between 1 and 7 days and with a heart failure diagnosis on that admission
hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days,
    CASE
      WHEN a.admission_type IN ('EMERGENCY','URGENT') THEN 'ED/Urgent'
      WHEN a.admission_type = 'ELECTIVE' THEN 'Elective'
      ELSE 'Other'
    END AS admission_type_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN pat_filtered p ON a.subject_id = p.subject_id
  WHERE DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 7
    -- require a heart failure diagnosis on the admission (ICD descriptions containing 'heart failure')
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dx
        ON d.icd_code = dx.icd_code
       AND d.icd_version = dx.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dx.long_title) LIKE '%heart failure%'
    )
    -- only keep the two desired strata for the final stratification (others can be dropped)
    AND a.admission_type IN ('EMERGENCY','URGENT','ELECTIVE')
),

-- Diagnostic events from HCPCS events (HOSP)
hcpcs_diag AS (
  SELECT
    h.hadm_id,
    CONCAT('hcpcs::', COALESCE(CAST(h.hcpcs_cd AS STRING), ''), '::', COALESCE(h.short_description,'')) AS descr,
    DATE(h.chartdate) AS event_date
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE h.hadm_id IS NOT NULL
    -- keyword filters applied later via lower(short_description)
    AND (
      LOWER(COALESCE(h.short_description, '')) LIKE '%xray%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%x-ray%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%ct%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%computed tomography%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%mri%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%magnetic resonance%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%ultrasound%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%echo%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%radiograph%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%radiology%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%ecg%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%ekg%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%electrocardiogram%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%eeg%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%pft%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%spiromet%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%pulmonary function%'
    )
),

-- Diagnostic events from ICD procedures (HOSP)
icdproc_diag AS (
  SELECT
    p.hadm_id,
    CONCAT('icdproc::', COALESCE(CAST(dp.long_title AS STRING), '')) AS descr,
    DATE(p.chartdate) AS event_date
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code
   AND p.icd_version = dp.icd_version
  WHERE p.hadm_id IS NOT NULL
    AND (
      LOWER(COALESCE(dp.long_title, '')) LIKE '%xray%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%x-ray%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%ct%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%computed tomography%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%mri%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%magnetic resonance%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%ultrasound%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%echo%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%radiograph%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%radiology%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%ecg%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%ekg%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%electrocardiogram%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%eeg%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%pft%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%spiromet%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%pulmonary function%'
    )
),

-- Diagnostic events from ICU procedureevents (use d_items label)
icu_proc_diag AS (
  SELECT
    pe.hadm_id,
    CONCAT('icu_proc::', COALESCE(CAST(di.label AS STRING), ''), '::', COALESCE(CAST(pe.value AS STRING), '')) AS descr,
    DATE(pe.starttime) AS event_date
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE pe.hadm_id IS NOT NULL
    AND (
      LOWER(COALESCE(di.label, '')) LIKE '%xray%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%x-ray%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%ct%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%computed tomography%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%mri%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%magnetic resonance%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%ultrasound%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%echo%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%radiograph%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%radiology%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%ecg%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%ekg%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%electrocardiogram%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%eeg%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%pft%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%spiromet%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%pulmonary function%'
      -- also check the free-text value field
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%ecg%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%eeg%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%pft%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%spiromet%'
    )
),

-- Union all diagnostic event sources and restrict to events that occurred during the admission window
diag_events AS (
  SELECT h.hadm_id, h.event_date FROM hcpcs_diag h
  UNION ALL
  SELECT p.hadm_id, p.event_date FROM icdproc_diag p
  UNION ALL
  SELECT i.hadm_id, i.event_date FROM icu_proc_diag i
),

-- Count diagnostics per admission (only events that occur within the admission date range)
diag_counts AS (
  SELECT
    a.hadm_id,
    COUNT(*) AS diag_count
  FROM hf_admissions a
  LEFT JOIN diag_events e
    ON e.hadm_id = a.hadm_id
    AND e.event_date BETWEEN DATE(a.admittime) AND DATE(a.dischtime)
  GROUP BY a.hadm_id
)

-- Final aggregation: mean diagnostics per admission by LOS bucket and admission type group
SELECT
  CASE WHEN los_days BETWEEN 1 AND 4 THEN '1-4' WHEN los_days BETWEEN 5 AND 7 THEN '5-7' ELSE 'other' END AS los_bucket,
  admission_type_group,
  COUNT(a.hadm_id) AS n_admissions,
  ROUND(AVG(COALESCE(dc.diag_count, 0)), 3) AS mean_noninvasive_diagnostics_per_admission
FROM hf_admissions a
LEFT JOIN diag_counts dc
  ON a.hadm_id = dc.hadm_id
WHERE admission_type_group IN ('ED/Urgent', 'Elective')
  AND los_days BETWEEN 1 AND 7
GROUP BY los_bucket, admission_type_group
ORDER BY los_bucket, admission_type_group;