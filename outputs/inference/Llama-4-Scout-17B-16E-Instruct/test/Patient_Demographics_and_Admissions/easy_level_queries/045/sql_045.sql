WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id, anchor_age, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age BETWEEN 51 AND 61 AND gender = 'M'
  ),

  -- Identify patients with pneumonia
  pneumonia_patients AS (
    SELECT DISTINCT di.subject_id, di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE d.long_title LIKE '%Pneumonia%' AND di.subject_id IN (SELECT subject_id FROM target_patients)
  ),

  -- Identify first ICU stay for each admission
  first_icu_stay AS (
    SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN pneumonia_patients p ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
    WHERE i.intime = (SELECT MIN(intime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE subject_id = i.subject_id AND hadm_id = i.hadm_id)
  ),

  -- Calculate ICU LOS
  icu_los AS (
    SELECT subject_id, hadm_id, stay_id, DATE_DIFF(TIMESTAMP(outtime), TIMESTAMP(intime), DAY) AS los_days
    FROM first_icu_stay
  ),

  -- Calculate percentiles
  percentiles AS (
    SELECT 
      APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25_los
    FROM icu_los
  )

-- Select the 25th percentile of ICU LOS
SELECT percentile_25_los
FROM percentiles;