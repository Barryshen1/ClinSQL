WITH
  -- 1. Identify the patient cohort: Males, 59-69 years old, with Heart Failure diagnosis
  patient_hf_admissions AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd
      ON adm.subject_id = dicd.subject_id AND adm.hadm_id = dicd.hadm_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 59 AND 69
      AND (
        (dicd.icd_version = 9 AND dicd.icd_code LIKE '428%') -- ICD-9 Heart Failure
        OR (dicd.icd_version = 10 AND dicd.icd_code LIKE 'I50%') -- ICD-10 Heart Failure
      )
  ),
  -- Ensure each patient-admission is unique after filtering for HF diagnoses
  distinct_hf_admissions AS (
    SELECT DISTINCT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      DATE_DIFF(dischtime, admittime, DAY) AS hosp_los_days
    FROM patient_hf_admissions
  ),
  -- 2. Identify all radiography/CT events from ICU chartevents and hospital procedures
  radiography_ct_events AS (
    -- Radiography/CT events from ICU chartevents
    SELECT
      ce.subject_id,
      ce.hadm_id,
      CAST(ce.charttime AS DATETIME) AS event_datetime -- Ensure consistent datetime type
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
    WHERE
      di.category IN ('Imaging', 'Radiology') -- Categories related to imaging/radiology
    GROUP BY
      ce.subject_id,
      ce.hadm_id,
      CAST(ce.charttime AS DATETIME) -- Group to ensure unique event_datetime per admission
    UNION ALL
    -- Radiography/CT events from hospital procedures_icd
    SELECT
      pi.subject_id,
      pi.hadm_id,
      CAST(pi.chartdate AS DATETIME) AS event_datetime -- Cast date to datetime for consistency
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    WHERE
      (
        pi.icd_version = 9 AND (pi.icd_code LIKE '87.%' OR pi.icd_code LIKE '88.%') -- ICD-9 Diagnostic Radiology & Other Diagnostic Imaging
      )
      OR (
        pi.icd_version = 10 AND pi.icd_code LIKE 'B%' -- ICD-10-PCS Imaging section
      )
    GROUP BY
      pi.subject_id,
      pi.hadm_id,
      CAST(pi.chartdate AS DATETIME) -- Group to ensure unique event_datetime per admission
  ),
  -- 3. Count radiography/CT events per admission
  admission_radiography_ct_counts AS (
    SELECT
      dha.subject_id,
      dha.hadm_id,
      COUNT(rce.event_datetime) AS radiography_ct_count -- Count distinct imaging events
    FROM distinct_hf_admissions AS dha
    LEFT JOIN radiography_ct_events AS rce
      ON dha.subject_id = rce.subject_id
      AND dha.hadm_id = rce.hadm_id
    GROUP BY
      dha.subject_id,
      dha.hadm_id
  ),
  -- 4. Final cohort with LOS category and ICU use status
  final_cohort AS (
    SELECT
      arc.subject_id,
      arc.hadm_id,
      arc.radiography_ct_count,
      dha.hosp_los_days,
      -- Classify hospital Length of Stay
      CASE
        WHEN dha.hosp_los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN dha.hosp_los_days BETWEEN 5 AND 8 THEN '5-8 days'
        ELSE NULL -- Exclude stays outside 1-8 days range
      END AS los_category,
      -- Determine if the admission involved an ICU stay
      CASE
        WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu WHERE icu.hadm_id = dha.hadm_id) THEN 'With ICU Stay'
        ELSE 'Without ICU Stay'
      END AS icu_use_category
    FROM admission_radiography_ct_counts AS arc
    INNER JOIN distinct_hf_admissions AS dha
      ON arc.subject_id = dha.subject_id
      AND arc.hadm_id = dha.hadm_id
    WHERE
      dha.hosp_los_days BETWEEN 1 AND 8 -- Only consider admissions with LOS between 1 and 8 days
  )
-- 5. Calculate 25th, 50th, and 75th percentiles
SELECT
  fc.los_category,
  fc.icu_use_category,
  APPROX_QUANTILES(fc.radiography_ct_count, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(fc.radiography_ct_count, 100)[OFFSET(50)] AS percentile_50,
  APPROX_QUANTILES(fc.radiography_ct_count, 100)[OFFSET(75)] AS percentile_75
FROM final_cohort AS fc
WHERE
  fc.los_category IS NOT NULL -- Exclude admissions with LOS outside the specified ranges
GROUP BY
  fc.los_category,
  fc.icu_use_category
ORDER BY
  fc.los_category,
  fc.icu_use_category;