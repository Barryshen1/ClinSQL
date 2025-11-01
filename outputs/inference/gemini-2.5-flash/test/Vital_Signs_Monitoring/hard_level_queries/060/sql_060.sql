WITH
  -- 1. Identify patients with Hyperosmolar Hyperglycemic State (HHS) based on ICD codes
  hhs_diagnoses AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND icd_code IN ('25020', '25021')) -- ICD-9 codes for Hyperosmolar coma/state
      OR (icd_version = 10 AND icd_code IN ('E1022', 'E1122')) -- ICD-10 codes for Type 1/2 diabetes with hyperosmolar hyperglycemic state
  ),

  -- 2. Establish the base cohort of male ICU patients aged 78-88
  base_cohort AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age,
      adm.hadm_id,
      adm.admittime,
      adm.hospital_expire_flag,
      icu.stay_id,
      icu.intime,
      icu.outtime,
      icu.los
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON p.subject_id = adm.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON adm.hadm_id = icu.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 78 AND 88
  ),

  -- 3. Assign cohort type (HHS or Control)
  patient_cohorts AS (
    SELECT
      bc.*,
      CASE
        WHEN hhs.hadm_id IS NOT NULL THEN 'HHS'
        ELSE 'Control'
      END AS cohort_type
    FROM
      base_cohort bc
    LEFT JOIN
      hhs_diagnoses hhs
      ON bc.hadm_id = hhs.hadm_id
  ),

  -- 4. Extract relevant vital signs and GCS within the first 48 hours of ICU admission
  --    and filter out invalid/erroneous measurements
  vitals_48h AS (
    SELECT
      pc.subject_id,
      pc.hadm_id,
      pc.stay_id,
      ce.itemid,
      ce.valuenum,
      ce.charttime
    FROM
      patient_cohorts pc
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON pc.subject_id = ce.subject_id AND pc.stay_id = ce.stay_id
    WHERE
      ce.charttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 48 HOUR)
      AND ce.valuenum IS NOT NULL
      AND ce.itemid IN (
        220045, -- Heart Rate (bpm)
        220050, 220179, -- Systolic Blood Pressure (mmHg)
        220210, 224690, -- Respiratory Rate (breaths/min)
        223762, -- Temperature Celsius (degC)
        220277, -- SpO2 (%)
        220739 -- GCS - Total (Score)
      )
      -- Apply robust filters for valuenum within physiologically plausible ranges
      AND (
        (ce.itemid = 220045 AND ce.valuenum BETWEEN 1 AND 250) OR -- HR
        (ce.itemid IN (220050, 220179) AND ce.valuenum BETWEEN 1 AND 300) OR -- SBP
        (ce.itemid IN (220210, 224690) AND ce.valuenum BETWEEN 0 AND 80) OR -- RR (can be 0 for ventilated patients)
        (ce.itemid = 223762 AND ce.valuenum BETWEEN 25 AND 45) OR -- Temp C
        (ce.itemid = 220277 AND ce.valuenum BETWEEN 1 AND 100) OR -- SpO2
        (ce.itemid = 220739 AND ce.valuenum BETWEEN 3 AND 15) -- GCS
      )
  ),

  -- 5. Determine abnormality for each measurement and classify vital sign type
  abnormal_vitals_flagged AS (
    SELECT
      v.subject_id,
      v.hadm_id,
      v.stay_id,
      v.charttime,
      CASE
        WHEN v.itemid = 220045 THEN 'HR'
        WHEN v.itemid IN (220050, 220179) THEN 'SBP'
        WHEN v.itemid IN (220210, 224690) THEN 'RR'
        WHEN v.itemid = 223762 THEN 'Temp'
        WHEN v.itemid = 220277 THEN 'SpO2'
        WHEN v.itemid = 220739 THEN 'GCS'
        ELSE NULL
      END AS vital_sign_type,
      v.valuenum,
      -- Set is_abnormal flag based on clinical thresholds
      CASE
        WHEN (v.itemid = 220045 AND (v.valuenum < 60 OR v.valuenum > 100)) THEN 1 -- HR
        WHEN (v.itemid IN (220050, 220179) AND (v.valuenum < 90 OR v.valuenum > 140)) THEN 1 -- SBP
        WHEN (v.itemid IN (220210, 224690) AND (v.valuenum < 10 OR v.valuenum > 24)) THEN 1 -- RR
        WHEN (v.itemid = 223762 AND (v.valuenum < 36 OR v.valuenum > 38.3)) THEN 1 -- Temp C
        WHEN (v.itemid = 220277 AND v.valuenum < 92) THEN 1 -- SpO2
        WHEN (v.itemid = 220739 AND v.valuenum < 13) THEN 1 -- GCS
        ELSE 0
      END AS is_abnormal
    FROM
      vitals_48h v
    WHERE
      -- Ensure vital_sign_type was correctly identified
      CASE
        WHEN v.itemid = 220045 THEN 'HR'
        WHEN v.itemid IN (220050, 220179) THEN 'SBP'
        WHEN v.itemid IN (220210, 224690) THEN 'RR'
        WHEN v.itemid = 223762 THEN 'Temp'
        WHEN v.itemid = 220277 THEN 'SpO2'
        WHEN v.itemid = 220739 THEN 'GCS'
        ELSE NULL
      END IS NOT NULL
  ),

  -- 6. Calculate Composite Instability Score per patient (stay_id)
  composite_instability_score AS (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      COUNT(DISTINCT vital_sign_type) AS score
    FROM
      abnormal_vitals_flagged
    WHERE
      is_abnormal = 1
    GROUP BY
      subject_id, hadm_id, stay_id
  ),

  -- 7. Calculate Mean Abnormal Vital Burden per patient (stay_id)
  mean_abnormal_vital_burden AS (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      AVG(proportion_abnormal) AS burden
    FROM (
      SELECT
        subject_id,
        hadm_id,
        stay_id,
        vital_sign_type,
        SUM(is_abnormal) * 1.0 / COUNT(*) AS proportion_abnormal
      FROM
        abnormal_vitals_flagged
      GROUP BY
        subject_id, hadm_id, stay_id, vital_sign_type
    )
    GROUP BY
      subject_id, hadm_id, stay_id
  ),

  -- 8. Combine all patient-level metrics
  patient_metrics AS (
    SELECT
      pc.subject_id,
      pc.hadm_id,
      pc.stay_id,
      pc.cohort_type,
      COALESCE(cis.score, 0) AS composite_instability_score,
      COALESCE(mab.burden, 0.0) AS mean_abnormal_vital_burden,
      pc.los AS icu_los_days,
      pc.hospital_expire_flag AS hospital_mortality
    FROM
      patient_cohorts pc
    LEFT JOIN
      composite_instability_score cis
      ON pc.stay_id = cis.stay_id
    LEFT JOIN
      mean_abnormal_vital_burden mab
      ON pc.stay_id = mab.stay_id
  )

-- 9. Aggregate results by cohort type to get percentiles and means
SELECT
  cohort_type,
  -- Composite Instability Score percentiles
  APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(25)] AS composite_score_p25,
  APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(50)] AS composite_score_median,
  APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(75)] AS composite_score_p75,

  -- Mean Abnormal Vital Burden percentiles
  APPROX_QUANTILES(mean_abnormal_vital_burden, 100)[OFFSET(25)] AS abnormal_burden_p25,
  APPROX_QUANTILES(mean_abnormal_vital_burden, 100)[OFFSET(50)] AS abnormal_burden_median,
  APPROX_QUANTILES(mean_abnormal_vital_burden, 100)[OFFSET(75)] AS abnormal_burden_p75,

  -- Mean ICU LOS
  AVG(icu_los_days) AS mean_icu_los_days,

  -- Mortality rate (mean of 0/1 flag)
  AVG(hospital_mortality) AS mortality_rate,

  -- Count of patients in each group (for context/sample size)
  COUNT(DISTINCT stay_id) AS num_icu_stays
FROM
  patient_metrics
GROUP BY
  cohort_type
ORDER BY
  cohort_type;