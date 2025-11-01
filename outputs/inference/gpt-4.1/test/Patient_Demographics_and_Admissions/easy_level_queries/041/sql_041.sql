WITH anticoagulant_drugs AS (
  SELECT 'warfarin' AS drug UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'enoxaparin' UNION ALL
  SELECT 'apixaban' UNION ALL
  SELECT 'rivaroxaban' UNION ALL
  SELECT 'dabigatran' UNION ALL
  SELECT 'fondaparinux' UNION ALL
  SELECT 'dalteparin' UNION ALL
  SELECT 'tinzaparin'
),
female_50_60 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 50 AND 60
),
first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),
anticoag_patients AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id
  FROM
    first_admissions fa
    JOIN female_50_60 f ON fa.subject_id = f.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON fa.hadm_id = p.hadm_id
    JOIN anticoagulant_drugs ad
      ON LOWER(p.drug) LIKE CONCAT('%', ad.drug, '%')
  WHERE
    fa.rn = 1
),
first_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id, icu.hadm_id ORDER BY icu.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
)
SELECT
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los_days
FROM
  anticoag_patients ap
  JOIN first_icu_stays icu
    ON ap.subject_id = icu.subject_id
    AND ap.hadm_id = icu.hadm_id
WHERE
  icu.rn = 1
  AND icu.los IS NOT NULL;