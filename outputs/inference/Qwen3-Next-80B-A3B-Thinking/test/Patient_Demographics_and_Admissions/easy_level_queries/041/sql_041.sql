WITH first_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
anticoagulant_patients AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id
  FROM first_admissions fa
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE p.hadm_id = fa.hadm_id
      AND p.drug_type = 'anticoagulant'
      AND p.starttime BETWEEN fa.admittime AND fa.dischtime
  )
),
first_icu_stays AS (
  SELECT 
    i.hadm_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  WHERE i.hadm_id IN (SELECT hadm_id FROM anticoagulant_patients)
)
SELECT 
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
FROM first_icu_stays
WHERE rn = 1;