WITH
  -- Step 1: target population - females aged 52–62
  eligible_women AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE lower(gender) = 'female'
      AND anchor_age BETWEEN 52 AND 62
  ),
  -- Step 2: patients who have ever received an anticoagulant
  anticoag_subjects AS (
    SELECT DISTINCT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE LOWER(drug) LIKE '%warfarin%'
       OR LOWER(drug) LIKE '%heparin%'
       OR LOWER(drug) LIKE '%enoxaparin%'
       OR LOWER(drug) LIKE '%dalteparin%'
       OR LOWER(drug) LIKE '%fondaparinux%'
       OR LOWER(drug) LIKE '%rivaroxaban%'
       OR LOWER(drug) LIKE '%apixaban%'
       OR LOWER(drug) LIKE '%edoxaban%'
       OR LOWER(drug) LIKE '%dabigatran%'
       OR LOWER(drug) LIKE '%argatroban%'
       OR LOWER(drug) LIKE '%bivalirudin%'
  ),
  -- Step 3: intersection - eligible patients who have received anticoagulants
  eligible_subjects AS (
    SELECT DISTINCT e.subject_id
    FROM eligible_women e
    JOIN anticoag_subjects a
      ON a.subject_id = e.subject_id
  ),
  -- Step 4: first admission per subject in the eligible cohort
  first_admission AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM (
      SELECT subject_id, hadm_id, admittime, dischtime,
             ROW_NUMBER() OVER (
               PARTITION BY subject_id
               ORDER BY admittime ASC, hadm_id ASC
             ) AS rn
      FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    ) AS a
    WHERE a.subject_id IN (SELECT subject_id FROM eligible_subjects)
      AND a.rn = 1
  ),
  -- Step 5: compute LOS in days for the first admission
  los_per_subject AS (
    SELECT fa.subject_id,
           DATE_DIFF(DATE(fa.dischtime), DATE(fa.admittime), DAY) AS los_days
    FROM first_admission fa
  ),
  -- Step 6: SD of LOS
  sd_result AS (
    SELECT STDDEV_SAMP(los_days) AS sd_los_days
    FROM los_per_subject
  )
-- Final output
SELECT * FROM sd_result;