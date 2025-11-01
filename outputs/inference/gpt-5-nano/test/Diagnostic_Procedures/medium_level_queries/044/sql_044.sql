WITH
  -- Step 1: female patients aged 62-72
  females_62_72 AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 62 AND 72
  ),

  -- Step 2: admissions with lower GI bleed
  gi_bleed_admissions AS (
    SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
    JOIN females_62_72 f ON a.subject_id = f.subject_id
    WHERE
      LOWER(ddi.long_title) LIKE '%gastrointestinal bleeding%'
      OR LOWER(ddi.long_title) LIKE '%lower gi%'
      OR LOWER(ddi.long_title) LIKE '%bleed%'
  ),

  -- Step 3: ICU flag per admission
  admissions_with_icu AS (
    SELECT g.hadm_id, g.subject_id, g.admittime, g.dischtime,
           MAX(CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_flag
    FROM gi_bleed_admissions g
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON g.hadm_id = i.hadm_id
    GROUP BY g.hadm_id, g.subject_id, g.admittime, g.dischtime
  ),

  -- Step 4: LOS bin per admission (only 1-3 or 4-7 days)
  admissions_with_los AS (
    SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime,
           CASE
             WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 3 THEN '1-3'
             WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 4 AND 7 THEN '4-7'
             ELSE NULL
           END AS los_bin,
           a.icu_flag
    FROM admissions_with_icu a
    WHERE DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
  ),

  -- Step 5: Non-invasive diagnostic counts from ICU chart events
  icu_test_counts AS (
    SELECT ce.hadm_id, ce.subject_id, COUNT(*) AS test_count
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    WHERE ce.subject_id IN (SELECT subject_id FROM females_62_72)
      AND ce.hadm_id IN (SELECT hadm_id FROM gi_bleed_admissions)
      AND (
        LOWER(di.label) LIKE '%ecg%' OR LOWER(di.label) LIKE '%eeg%' OR LOWER(di.label) LIKE '%pft%'
        OR LOWER(di.label) LIKE '%imaging%' OR LOWER(di.label) LIKE '%radiology%' OR LOWER(di.label) LIKE '%ct%'
        OR LOWER(di.label) LIKE '%mri%' OR LOWER(di.label) LIKE '%x-ray%' OR LOWER(di.label) LIKE '%ultrasound%'
      )
    GROUP BY ce.hadm_id, ce.subject_id
  )

SELECT
  a.los_bin,
  CASE WHEN a.icu_flag = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
  AVG(COALESCE(t.test_count, 0)) AS mean_noninvasive_tests_per_admission
FROM admissions_with_los a
LEFT JOIN icu_test_counts t
  ON a.hadm_id = t.hadm_id
 AND a.subject_id = t.subject_id
GROUP BY a.los_bin, icu_status
ORDER BY a.los_bin, icu_status;