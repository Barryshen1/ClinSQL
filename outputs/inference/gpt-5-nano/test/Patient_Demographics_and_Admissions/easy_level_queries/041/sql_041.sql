WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 50 AND 60
),
first_admission_rank AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM first_admissions
),
first_admission AS (
  SELECT
    subject_id,
    hadm_id
  FROM first_admission_rank
  WHERE rn = 1
),
first_icu AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY f.subject_id, f.hadm_id ORDER BY i.intime) AS rn
  FROM first_admission f
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.subject_id = f.subject_id
   AND i.hadm_id = f.hadm_id
),
first_icu_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los
  FROM first_icu
  WHERE rn = 1
),
anticoagulant_icu AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.los
  FROM first_icu_per_admission AS f
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON di.itemid = ie.itemid
    WHERE ie.subject_id = f.subject_id
      AND ie.stay_id = f.stay_id
      AND (
        LOWER(di.label) LIKE '%heparin%'
        OR LOWER(di.label) LIKE '%warfarin%'
        OR LOWER(di.label) LIKE '%enoxaparin%'
        OR LOWER(di.label) LIKE '%lovenox%'
        OR LOWER(di.label) LIKE '%fondaparinux%'
        OR LOWER(di.label) LIKE '%apixaban%'
        OR LOWER(di.label) LIKE '%rivaroxaban%'
        OR LOWER(di.label) LIKE '%dabigatran%'
        OR LOWER(di.label) LIKE '%edoxaban%'
        OR LOWER(di.label) LIKE '%tinzaparin%'
        OR LOWER(di.label) LIKE '%nadroparin%'
        OR LOWER(di.label) LIKE '%argatroban%'
        OR LOWER(di.label) LIKE '%bivalirudin%'
      )
  )
),
median_calc AS (
  -- Collect LOS values for all qualifying ICU stays into a single ordered array
  SELECT ARRAY_AGG(los ORDER BY los) AS los_arr
  FROM anticoagulant_icu
),
median_final AS (
  SELECT los_arr, ARRAY_LENGTH(los_arr) AS n
  FROM median_calc
)
SELECT
  CASE
    WHEN n = 0 THEN NULL
    ELSE (los_arr[OFFSET(CAST((n - 1) / 2 AS INT64))] + los_arr[OFFSET(CAST(n / 2 AS INT64))]) / 2.0
  END AS median_icu_los_days
FROM median_final;