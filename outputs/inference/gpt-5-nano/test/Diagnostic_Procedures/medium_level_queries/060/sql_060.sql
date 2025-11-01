WITH
  -- Step 1: identify admissions meeting the cohort (male, age 49-59, primary HF)
  heart_admissions AS (
    SELECT
      a.hadm_id,
      a.subject_id,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON di.subject_id = a.subject_id
     AND di.hadm_id = a.hadm_id
    WHERE
      (p.gender = 'M' OR p.gender = 'Male')
      -- approximate age at admission
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
      -- primary HF
      AND di.seq_num = 1
      AND di.icd_code LIKE '428.%'
      AND di.icd_version = 9
      AND a.admittime IS NOT NULL
      AND a.dischtime IS NOT NULL
  ),

  -- Step 2: ICU usage flag per admission (1 if any ICU stay, else 0)
  icu_flags AS (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY hadm_id
  ),
  icu_flags_all AS (
    SELECT h.hadm_id,
           CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_use
    FROM heart_admissions h
    LEFT JOIN icu_flags i ON h.hadm_id = i.hadm_id
  ),

  -- Step 3: count CT/MRI imaging events per admission (ICU data)
  imaging_counts AS (
    SELECT hadm_id,
           COUNT(*) AS imaging_ct_mri_events
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    WHERE (di.label LIKE '%CT%' OR di.label LIKE '%MRI%')
      AND ce.charttime IS NOT NULL
    GROUP BY hadm_id
  ),

  -- Step 4: assemble per-admission results with LOS groups and ICU flag
  final AS (
    SELECT
      h.hadm_id,
      h.subject_id,
      h.hosp_los_days,
      CASE
        WHEN h.hosp_los_days BETWEEN 1 AND 4 THEN '1-4'
        WHEN h.hosp_los_days BETWEEN 5 AND 7 THEN '5-7'
        ELSE NULL
      END AS los_group,
      u.icu_use,
      COALESCE(ic.imaging_ct_mri_events, 0) AS imaging_ct_mri_events
    FROM heart_admissions h
    JOIN icu_flags_all u ON h.hadm_id = u.hadm_id
    LEFT JOIN imaging_counts ic ON h.hadm_id = ic.hadm_id
    WHERE CASE
            WHEN h.hosp_los_days BETWEEN 1 AND 4 THEN '1-4'
            WHEN h.hosp_los_days BETWEEN 5 AND 7 THEN '5-7'
            ELSE NULL
          END IS NOT NULL
  )

SELECT
  los_group,
  icu_use,
  COUNT(*) AS admission_count,
  AVG(imaging_ct_mri_events) AS mean_ct_mri_per_admission
FROM final
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;