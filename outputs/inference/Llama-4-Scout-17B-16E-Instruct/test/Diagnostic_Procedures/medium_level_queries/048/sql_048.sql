WITH 
  -- Define heart failure ICD codes
  heart_failure AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Heart failure%'
  ),

  -- Identify patients and admissions of interest
  patients_of_interest AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.admission_type,
           p.anchor_age, p.gender, a.admission_location
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN (SELECT icd_code FROM heart_failure)
    )
  ),

  -- Calculate LOS and categorize
  los_categories AS (
    SELECT poi.hadm_id,
           poi.admission_type,
           poi.admission_location,
           CASE
             WHEN DATE_DIFF(poi.dischtime, poi.admittime, 'DAY') BETWEEN 1 AND 3 THEN 'LOS 1-3'
             WHEN DATE_DIFF(poi.dischtime, poi.admittime, 'DAY') BETWEEN 4 AND 7 THEN 'LOS 4-7'
             ELSE 'Outside of Interest'
           END AS los_category
    FROM patients_of_interest poi
  ),

  -- Identify MRI/CT events
  mri_ct_events AS (
    SELECT hadm_id, COUNT(*) as mri_ct_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid IN (
      SELECT itemid
      FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE label LIKE '%MRI%' OR label LIKE '%CT%'
    )
    GROUP BY hadm_id
  )

-- Final aggregation, considering primary vs secondary admission
SELECT 
  lc.los_category,
  lc.admission_type AS admission_category,
  COUNT(DISTINCT lc.hadm_id) as admission_count,
  COALESCE(AVG(mce.mri_ct_count), 0) as mean_mri_ct_per_admission
FROM los_categories lc
LEFT JOIN mri_ct_events mce ON lc.hadm_id = mce.hadm_id
GROUP BY lc.los_category, lc.admission_type
ORDER BY lc.los_category, lc.admission_type;