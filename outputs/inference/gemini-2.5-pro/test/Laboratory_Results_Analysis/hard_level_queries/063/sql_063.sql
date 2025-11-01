WITH
  -- Step 1: Define the set of critical lab itemids
  critical_lab_ids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE itemid IN (
      50983, -- Sodium
      50971, -- Potassium
      50902, -- Chloride
      50882, -- Bicarbonate
      50912, -- Creatinine
      51006, -- Urea Nitrogen (BUN)
      50931, -- Glucose
      51301, -- White Blood Cells (WBC)
      51222, -- Hemoglobin
      51221, -- Hematocrit
      51265  -- Platelet Count
    )
  ),

  -- Step 2: Identify the cohort of female patients, aged 53-63, with Pulmonary Embolism (PE)
  pe_cohort AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND (
        (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age
      ) BETWEEN 53 AND 63
      AND adm.hadm_id IN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
          STARTS_WITH(icd_code, 'I26') -- ICD-10 for PE
          OR STARTS_WITH(icd_code, '4151') -- ICD-9 for PE
      )
  ),

  -- Step 3: Calculate the "Lab Instability Score" for each patient in the cohort
  lab_instability_scores AS (
    WITH
      abnormal_labs_in_cohort AS (
        SELECT
          cohort.hadm_id,
          lab.itemid
        FROM pe_cohort AS cohort
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS lab
          ON cohort.hadm_id = lab.hadm_id
        WHERE
          lab.itemid IN (SELECT itemid FROM critical_lab_ids)
          AND lab.valuenum IS NOT NULL
          AND lab.charttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR)
          AND (lab.valuenum < lab.ref_range_lower OR lab.valuenum > lab.ref_range_upper)
      )
    SELECT
      cohort.hadm_id,
      COALESCE(COUNT(DISTINCT ab_lab.itemid), 0) AS lab_instability_score
    FROM pe_cohort AS cohort
    LEFT JOIN abnormal_labs_in_cohort AS ab_lab
      ON cohort.hadm_id = ab_lab.hadm_id
    GROUP BY cohort.hadm_id
  ),

  -- Step 4: Find the 75th percentile threshold of the score
  score_threshold AS (
    SELECT
      APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS p75_score
    FROM lab_instability_scores
  ),

  -- Step 5: Identify the high-risk group (score >= 75th percentile)
  high_risk_group AS (
    SELECT
      lis.hadm_id,
      cohort.dischtime,
      cohort.admittime,
      cohort.hospital_expire_flag
    FROM lab_instability_scores AS lis
    INNER JOIN pe_cohort AS cohort
      ON lis.hadm_id = cohort.hadm_id
    CROSS JOIN score_threshold
    WHERE lis.lab_instability_score >= score_threshold.p75_score
  ),

  -- Step 6: Calculate mortality and LOS for the high-risk group
  high_risk_stats AS (
    SELECT
      AVG(hrg.hospital_expire_flag) * 100 AS high_risk_mortality_percent,
      AVG(DATETIME_DIFF(hrg.dischtime, hrg.admittime, DAY)) AS high_risk_mean_los_days
    FROM high_risk_group AS hrg
  ),

  -- Step 7: Calculate and compare the rate of abnormal labs
  comparison_rates AS (
    WITH
      all_critical_labs_flagged AS (
        SELECT
          lab.hadm_id,
          CASE
            WHEN lab.valuenum IS NOT NULL AND (lab.valuenum < lab.ref_range_lower OR lab.valuenum > lab.ref_range_upper) THEN 1
            ELSE 0
          END AS is_abnormal,
          CASE
            WHEN lab.hadm_id IN (SELECT hadm_id FROM high_risk_group) THEN 1
            ELSE 0
          END AS is_high_risk
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS lab
        WHERE
          lab.itemid IN (SELECT itemid FROM critical_lab_ids)
          AND lab.valuenum IS NOT NULL
      )
    SELECT
      SAFE_DIVIDE(SUM(is_abnormal * is_high_risk), SUM(is_high_risk)) AS high_risk_abnormal_lab_rate,
      SAFE_DIVIDE(SUM(is_abnormal), COUNT(hadm_id)) AS all_inpatients_abnormal_lab_rate
    FROM all_critical_labs_flagged
  )

-- Final Step: Combine all results into a single output row
SELECT
  st.p75_score AS lab_instability_score_75th_percentile,
  hrs.high_risk_mortality_percent,
  hrs.high_risk_mean_los_days,
  cr.high_risk_abnormal_lab_rate,
  cr.all_inpatients_abnormal_lab_rate
FROM
  score_threshold AS st,
  high_risk_stats AS hrs,
  comparison_rates AS cr;