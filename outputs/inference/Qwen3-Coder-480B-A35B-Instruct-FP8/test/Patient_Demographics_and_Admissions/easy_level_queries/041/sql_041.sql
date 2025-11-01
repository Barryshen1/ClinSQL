WITH first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
first_icu_stays AS (
  SELECT
    hadm_id,
    stay_id,
    los,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 50 AND 60
),
anticoag_patients AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) IN (
    'warfarin', 'heparin', 'enoxaparin', 'dalteparin', 'fondaparinux',
    'rivaroxaban', 'apixaban', 'dabigatran', 'edoxaban'
  )
)
SELECT
  APPROX_QUANTILES(los, 2)[ORDINAL(1)] AS median_icu_los_days
FROM first_admissions fa
JOIN first_icu_stays fis
  ON fa.hadm_id = fis.hadm_id
JOIN patients_filtered pf
  ON fa.subject_id = pf.subject_id
JOIN anticoag_patients ap
  ON fa.subject_id = ap.subject_id
WHERE fa.rn = 1 AND fis.rn = 1;