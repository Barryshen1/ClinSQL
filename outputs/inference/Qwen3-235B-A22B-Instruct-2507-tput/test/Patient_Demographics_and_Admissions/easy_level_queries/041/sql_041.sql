WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age >= 50
    AND anchor_age <= 60
),
first_admission AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p
    ON a.subject_id = p.subject_id
  WHERE a.admittime = (
    SELECT MIN(a2.admittime)
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a2
    WHERE a2.subject_id = a.subject_id
  )
),
anticoagulant_use AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id
  FROM first_admission fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    ON fa.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) IN (
    'warfarin', 'heparin', 'enoxaparin', 'dalteparin', 'fondaparinux',
    'dabigatran', 'rivaroxaban', 'apixaban', 'edoxaban', 'betrixaban',
    'argatroban', 'bivalirudin', 'lepirudin'
  )
),
first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN anticoagulant_use a
    ON i.hadm_id = a.hadm_id
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los_days
FROM first_icu_stay
WHERE rn = 1;