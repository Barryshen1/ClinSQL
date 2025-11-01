WITH first_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS adm_seq
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
filtered_patients AS (
  SELECT 
    subject_id,
    hadm_id
  FROM first_admissions
  WHERE adm_seq = 1
    AND age_at_admission BETWEEN 50 AND 60
),
anticoagulant_users AS (
  SELECT 
    fp.subject_id,
    fp.hadm_id
  FROM filtered_patients fp
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.subject_id = fp.subject_id
      AND pr.hadm_id = fp.hadm_id
      AND (
        LOWER(pr.drug) LIKE '%warfarin%' OR
        LOWER(pr.drug) LIKE '%heparin%' OR
        LOWER(pr.drug) LIKE '%enoxaparin%' OR
        LOWER(pr.drug) LIKE '%dalteparin%' OR
        LOWER(pr.drug) LIKE '%fondaparinux%' OR
        LOWER(pr.drug) LIKE '%dabigatran%' OR
        LOWER(pr.drug) LIKE '%rivaroxaban%' OR
        LOWER(pr.drug) LIKE '%apixaban%' OR
        LOWER(pr.drug) LIKE '%edoxaban%' OR
        LOWER(pr.drug) LIKE '%argatroban%' OR
        LOWER(pr.drug) LIKE '%bivalirudin%'
      )
  )
),
first_icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS icu_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN anticoagulant_users au
    ON i.subject_id = au.subject_id AND i.hadm_id = au.hadm_id
),
icu_los AS (
  SELECT 
    TIMESTAMP_DIFF(outtime, intime, SECOND) / (24 * 60 * 60) AS icu_los_days
  FROM first_icu_stays
  WHERE icu_seq = 1
)
SELECT 
  APPROX_QUANTILES(icu_los_days, 100)[OFFSET(50)] AS median_icu_los_days
FROM icu_los;