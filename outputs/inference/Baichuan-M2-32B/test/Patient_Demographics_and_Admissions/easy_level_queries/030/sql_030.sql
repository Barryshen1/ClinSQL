WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN (
    SELECT subject_id, MIN(admittime) AS first_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
  ) first ON a.subject_id = first.subject_id AND a.admittime = first.first_admittime
  WHERE a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
),
patients_with_age AS (
  SELECT 
    p.subject_id,
    p.anchor_year,
    p.anchor_age,
    p.anchor_year - p.anchor_age AS birth_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
),
age_filtered AS (
  SELECT 
    f.*,
    EXTRACT(YEAR FROM f.admittime) - p.birth_year AS age_at_admission
  FROM first_admissions f
  INNER JOIN patients_with_age p ON f.subject_id = p.subject_id
  WHERE EXTRACT(YEAR FROM f.admittime) - p.birth_year BETWEEN 52 AND 62
),
anticoagulant_list AS (
  SELECT 'warfarin' AS drug_name
  UNION ALL SELECT 'heparin'
  UNION ALL SELECT 'enoxaparin'
  UNION ALL SELECT 'apixaban'
  UNION ALL SELECT 'rivaroxaban'
  UNION ALL SELECT 'dabigatran'
  UNION ALL SELECT 'fondaparinux'
  UNION ALL SELECT 'fondaparinux sodium'
  UNION ALL SELECT 'dalteparin'
  UNION ALL SELECT 'tinzaparin'
  UNION ALL SELECT 'argatroban'
  UNION ALL SELECT 'bivalirudin'
  UNION ALL SELECT 'desirudin'
  UNION ALL SELECT 'lepirudin'
  UNION ALL SELECT 'reptilase'
  UNION ALL SELECT 'hirudin'
  UNION ALL SELECT 'thrombin'
),
anticoagulant_in_first_admission AS (
  SELECT 
    af.subject_id,
    af.hadm_id,
    af.los_days
  FROM age_filtered af
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN anticoagulant_list a 
      ON LOWER(p.drug) LIKE CONCAT('%', LOWER(a.drug_name), '%')
    WHERE p.hadm_id = af.hadm_id
      AND p.starttime BETWEEN af.admittime AND af.dischtime
  )
)
SELECT STDDEV_SAMP(los_days) AS sd_los
FROM anticoagulant_in_first_admission;