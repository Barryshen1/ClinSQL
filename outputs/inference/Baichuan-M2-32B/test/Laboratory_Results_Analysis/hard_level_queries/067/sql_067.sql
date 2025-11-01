WITH
  -- Step 1: Eligible patients (female, age 53-63)
  eligible_patients AS (
    SELECT
      p.subject_id,
      p.anchor_age,
      p.anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 53 AND 63
  ),
  -- Step 2: ACS patients (with ICD-10 codes I20-I25)
  acs_patients AS (
    SELECT
      d.subject_id,
      d.hadm_id,
      d.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN eligible_patients ep
      ON d.subject_id = ep.subject_id
    WHERE d.icd_version = 10
      AND d.icd_code BETWEEN 'I20' AND 'I25'
  ),
  -- Step 3: Non-ACS controls (same age/gender, without ACS diagnosis)
  non_acs_controls AS (
    SELECT
      p.subject_id,
      a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN eligible_patients p
      ON a.subject_id = p.subject_id
    WHERE NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = p.subject_id
        AND d.icd_version = 10
        AND d.icd_code BETWEEN 'I20' AND 'I25'
    )
    -- Ensure we have at least one admission for the control
    AND a.hadm_id IS NOT NULL
  ),
  -- Step 4: Critical lab categories (Electrolytes, Cardiac Enzymes, Renal Function, Lipids, Hematology)
  critical_labs AS (
    SELECT
      li.itemid,
      li.category
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    WHERE li.category IN (
      'Electrolytes',
      'Cardiac Enzymes',
      'Renal Function',
      'Lipids',
      'Hematology'
    )
  ),
  -- Step 5: Lab events for critical labs within 72 hours of admission for ACS and controls
  lab_events_72h AS (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.itemid,
      le.charttime,
      le.valuenum,
      le.valueuom,
      le.ref_range_lower,
      le.ref_range_upper,
      le.flag,
      -- Compute abnormal flag
      CASE
        WHEN le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL THEN
          CASE
            WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1
            ELSE 0
          END
        WHEN le.flag IN ('H', 'L') THEN 1
        ELSE 0
      END AS is_abnormal
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN critical_labs cl
      ON le.itemid = cl.itemid
    WHERE le.valuenum IS NOT NULL
  ),
  -- Step 6: Admissions with time details for eligible patients
  admissions_with_time AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN eligible_patients ep
      ON a.subject_id = ep.subject_id
  ),
  -- Step 7: Filter lab events to 72 hours from admittime
  lab_events_72h_filtered AS (
    SELECT
      le.*,
      a.admittime
    FROM lab_events_72h le
    INNER JOIN admissions_with_time a
      ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
    WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  ),
  -- Step 8: For each patient and category, mark if there's at least one abnormal result
  patient_category_abnormal AS (
    SELECT
      le.subject_id,
      le.hadm_id,
      cl.category,
      MAX(CASE WHEN le.is_abnormal = 1 THEN 1 ELSE 0 END) AS has_abnormal
    FROM lab_events_72h_filtered le
    INNER JOIN critical_labs cl
      ON le.itemid = cl.itemid
    GROUP BY le.subject_id, le.hadm_id, cl.category
  ),
  -- Step 9: Instability score per patient (count of categories with abnormal results)
  instability_score AS (
    SELECT
      p.subject_id,
      p.hadm_id,
      COUNT(DISTINCT CASE WHEN pa.has_abnormal = 1 THEN pa.category END) AS instability_score
    FROM admissions_with_time p
    LEFT JOIN patient_category_abnormal pa
      ON p.subject_id = pa.subject_id AND p.hadm_id = pa.hadm_id
    GROUP BY p.subject_id, p.hadm_id
  ),
  -- Step 10: ACS patients with instability score and quartiles
  acs_with_score AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.hospital_expire_flag,
      a.los_days,
      i.instability_score,
      -- Assign quartiles over the ACS cohort
      NTILE(4) OVER (ORDER BY i.instability_score) AS quartile
    FROM acs_patients a
    INNER JOIN instability_score i
      ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  ),
  -- Step 11: Controls with instability score (for comparison)
  controls_with_score AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      i.instability_score
    FROM non_acs_controls c
    INNER JOIN instability_score i
      ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
  ),
  -- Step 12: Report for ACS cohort: mortality and avg LOS per quartile
  acs_report AS (
    SELECT
      quartile,
      AVG(hospital_expire_flag) * 100 AS mortality_percent,
      AVG(los_days) AS avg_los_days
    FROM acs_with_score
    GROUP BY quartile
  ),
  -- Step 13: Compare critical lab rates (any abnormality) between ACS and controls
  acs_abnormal_rate AS (
    SELECT
      COUNT(DISTINCT subject_id) AS total_acs,
      SUM(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) AS abnormal_count,
      (SUM(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id)) AS abnormal_rate
    FROM acs_with_score
  ),
  controls_abnormal_rate AS (
    SELECT
      COUNT(DISTINCT subject_id) AS total_controls,
      SUM(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) AS abnormal_count,
      (SUM(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id)) AS abnormal_rate
    FROM controls_with_score
  ),
  comparison AS (
    SELECT
      a.abnormal_rate AS acs_abnormal_rate,
      c.abnormal_rate AS controls_abnormal_rate,
      (a.abnormal_rate - c.abnormal_rate) AS difference
    FROM acs_abnormal_rate a, controls_abnormal_rate c
  )
-- Final output: ACS quartile report and comparison
SELECT * FROM acs_report
UNION ALL
SELECT 'Comparison', acs_abnormal_rate, controls_abnormal_rate, difference
FROM comparison;