WITH
cohort_diagnoses AS (
  -- First, find hospital admissions (hadm_id) with both T2DM and HF diagnoses
  SELECT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    -- Use broader search terms to capture variations
    LOWER(d.long_title) LIKE '%type 2 diabetes mellitus%' OR LOWER(d.long_title) LIKE '%heart failure%'
  GROUP BY
    di.hadm_id
  -- The HAVING clause ensures the admission has at least one of each diagnosis type
  HAVING
    COUNT(DISTINCT CASE WHEN LOWER(d.long_title) LIKE '%type 2 diabetes mellitus%' THEN d.icd_code END) > 0
    AND COUNT(DISTINCT CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN d.icd_code END) > 0
),

cohort AS (
  -- Define the patient cohort: Female, 83-93 years old, with T2DM and HF
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN cohort_diagnoses AS cd
    ON a.hadm_id = cd.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),

insulin_events AS (
  -- Find all insulin prescriptions for the cohort and classify the regimen type
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    pr.starttime,
    -- If pharmacy table indicates a sliding scale, classify as such. Otherwise, classify by drug name.
    CASE
      WHEN ph.sliding_scale = 'Yes' THEN 'Sliding Scale'
      WHEN LOWER(pr.drug) LIKE '%glargine%' OR LOWER(pr.drug) LIKE '%lantus%' OR LOWER(pr.drug) LIKE '%detemir%' OR LOWER(pr.drug) LIKE '%levemir%' OR LOWER(pr.drug) LIKE '%degludec%' OR LOWER(pr.drug) LIKE '%toujeo%' OR LOWER(pr.drug) LIKE '%tresiba%' OR LOWER(pr.drug) LIKE '%basaglar%' THEN 'Basal'
      WHEN LOWER(pr.drug) LIKE '%lispro%' OR LOWER(pr.drug) LIKE '%humalog%' OR LOWER(pr.drug) LIKE '%aspart%' OR LOWER(pr.drug) LIKE '%novolog%' OR LOWER(pr.drug) LIKE '%glulisine%' OR LOWER(pr.drug) LIKE '%apidra%' OR LOWER(pr.drug) LIKE '%regular%' OR LOWER(pr.drug) LIKE '%humulin%' OR LOWER(pr.drug) LIKE '%novolin%' THEN 'Bolus'
      ELSE NULL
    END AS regimen_type
  FROM cohort AS c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON c.hadm_id = pr.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` AS ph
    ON pr.pharmacy_id = ph.pharmacy_id
  WHERE
    LOWER(pr.drug) LIKE '%insulin%'
    -- Ensure the prescription is within the hospital stay
    AND pr.starttime BETWEEN c.admittime AND c.dischtime
),

first_initiations AS (
  -- For each admission, find the first time each regimen type was initiated
  SELECT
    hadm_id,
    regimen_type,
    MIN(starttime) AS first_starttime
  FROM insulin_events
  WHERE
    regimen_type IS NOT NULL
  GROUP BY
    hadm_id,
    regimen_type
),

initiation_flags AS (
  -- Create flags for each patient indicating if they initiated a regimen in the specified time windows
  SELECT
    c.hadm_id,
    MAX(CASE WHEN fi.regimen_type = 'Basal' AND fi.first_starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS init_basal_first_48h,
    MAX(CASE WHEN fi.regimen_type = 'Bolus' AND fi.first_starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS init_bolus_first_48h,
    MAX(CASE WHEN fi.regimen_type = 'Sliding Scale' AND fi.first_starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS init_ss_first_48h,
    MAX(CASE WHEN fi.regimen_type = 'Basal' AND fi.first_starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS init_basal_final_12h,
    MAX(CASE WHEN fi.regimen_type = 'Bolus' AND fi.first_starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS init_bolus_final_12h,
    MAX(CASE WHEN fi.regimen_type = 'Sliding Scale' AND fi.first_starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS init_ss_final_12h
  FROM cohort AS c
  LEFT JOIN first_initiations AS fi
    ON c.hadm_id = fi.hadm_id
  GROUP BY
    c.hadm_id
),

final_calcs AS (
  -- Aggregate the flags to get total counts for each category
  SELECT
    COUNT(hadm_id) AS total_patients,
    SUM(init_basal_first_48h) AS count_basal_first_48h,
    SUM(init_bolus_first_48h) AS count_bolus_first_48h,
    SUM(init_ss_first_48h) AS count_ss_first_48h,
    SUM(CASE WHEN init_basal_first_48h = 1 AND init_bolus_first_48h = 1 THEN 1 ELSE 0 END) AS count_basal_bolus_first_48h,
    SUM(init_basal_final_12h) AS count_basal_final_12h,
    SUM(init_bolus_final_12h) AS count_bolus_final_12h,
    SUM(init_ss_final_12h) AS count_ss_final_12h,
    SUM(CASE WHEN init_basal_final_12h = 1 AND init_bolus_final_12h = 1 THEN 1 ELSE 0 END) AS count_basal_bolus_final_12h
  FROM initiation_flags
)

-- Format the final output table
SELECT
  'Basal' AS insulin_regimen,
  ROUND(100.0 * count_basal_first_48h / total_patients, 1) AS pct_first_48h,
  ROUND(100.0 * count_basal_final_12h / total_patients, 1) AS pct_final_12h,
  ROUND((100.0 * count_basal_final_12h / total_patients) - (100.0 * count_basal_first_48h / total_patients), 1) AS net_change_pct
FROM final_calcs
UNION ALL
SELECT
  'Bolus' AS insulin_regimen,
  ROUND(100.0 * count_bolus_first_48h / total_patients, 1) AS pct_first_48h,
  ROUND(100.0 * count_bolus_final_12h / total_patients, 1) AS pct_final_12h,
  ROUND((100.0 * count_bolus_final_12h / total_patients) - (100.0 * count_bolus_first_48h / total_patients), 1) AS net_change_pct
FROM final_calcs
UNION ALL
SELECT
  'Basal-Bolus' AS insulin_regimen,
  ROUND(100.0 * count_basal_bolus_first_48h / total_patients, 1) AS pct_first_48h,
  ROUND(100.0 * count_basal_bolus_final_12h / total_patients, 1) AS pct_final_12h,
  ROUND((100.0 * count_basal_bolus_final_12h / total_patients) - (100.0 * count_basal_bolus_first_48h / total_patients), 1) AS net_change_pct
FROM final_calcs
UNION ALL
SELECT
  'Sliding Scale' AS insulin_regimen,
  ROUND(100.0 * count_ss_first_48h / total_patients, 1) AS pct_first_48h,
  ROUND(100.0 * count_ss_final_12h / total_patients, 1) AS pct_final_12h,
  ROUND((100.0 * count_ss_final_12h / total_patients) - (100.0 * count_ss_first_48h / total_patients), 1) AS net_change_pct
FROM final_calcs;