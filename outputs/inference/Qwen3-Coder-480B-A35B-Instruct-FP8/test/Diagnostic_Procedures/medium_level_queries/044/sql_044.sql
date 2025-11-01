WITH cohort AS (
  -- Define the cohort: females aged 62–72
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 62 AND 72
),

admissions_with_los AS (
  -- Get admissions with LOS and ICU status
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 1
      ELSE 0
    END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort c ON a.subject_id = c.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),

lower_gi_admissions AS (
  -- Identify admissions with lower GI bleed diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%lower gastrointestinal hemorrhage%'
),

noninvasive_procedures AS (
  -- Identify non-invasive diagnostics (imaging, ECG/EEG/PFT)
  SELECT
    p.hadm_id,
    COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(LOWER(d.long_title), r'(ecg|eeg|pft|imaging|ct|mr|ultrasound|x-ray)')
    AND LOWER(d.long_title) NOT LIKE '%invasive%'
  GROUP BY p.hadm_id
),

admissions_with_proc AS (
  -- Combine admissions with procedure counts
  SELECT
    a.hadm_id,
    a.los_days,
    a.icu_flag,
    COALESCE(p.proc_count, 0) AS proc_count
  FROM admissions_with_los a
  LEFT JOIN noninvasive_procedures p ON a.hadm_id = p.hadm_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM lower_gi_admissions)
),

los_grouped AS (
  -- Assign LOS group
  SELECT *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Other'
    END AS los_group
  FROM admissions_with_proc
  WHERE los_days BETWEEN 1 AND 7
)

-- Final aggregation: mean number of diagnostics by LOS group and ICU status
SELECT
  los_group,
  icu_flag,
  AVG(proc_count) AS mean_diagnostics_per_admission
FROM los_grouped
GROUP BY los_group, icu_flag
ORDER BY los_group, icu_flag;