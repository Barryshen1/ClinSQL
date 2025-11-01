WITH first_admission AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn_adm
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions
),
first_icu_stay AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn_icu
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
),
anticoagulant_patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  WHERE LOWER(p.drug) IN (
    'warfarin', 'heparin', 'enoxaparin', 'apixaban', 'rivaroxaban', 
    'dabigatran', 'dalteparin', 'tinzaparin', 'fondaparinux'
  )
),
filtered_patients AS (
  SELECT 
    pat.subject_id,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients pat
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
    AND EXISTS (
      SELECT 1 
      FROM anticoagulant_patients ap 
      WHERE ap.subject_id = pat.subject_id
    )
)
SELECT 
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY fis.los) AS median_icu_los_days
FROM filtered_patients fp
JOIN first_admission fa ON fp.subject_id = fa.subject_id AND fa.rn_adm = 1
JOIN first_icu_stay fis ON fa.hadm_id = fis.hadm_id AND fis.rn_icu = 1;