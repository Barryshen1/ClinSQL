WITH
  -- Step 1: Identify the cohort of female inpatients, aged 53-63, with a post-cardiac arrest diagnosis.
  cohort_admissions AS (
    SELECT DISTINCT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 53 AND 63
      AND LOWER(d_dx.long_title) LIKE '%cardiac arrest%'
  ),

  -- Step 2: For each patient in the cohort, calculate the "instability score" = count of abnormal labs in the first 48h.
  cohort_lab_scores AS (
    SELECT
      c.hadm_id,
      COALESCE(COUNT(le.labevent_id), 0) AS instability_score
    FROM cohort_admissions AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON c.hadm_id = le.hadm_id
      AND le.flag = 'abnormal'
      AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    GROUP BY
      c.hadm_id
  ),

  -- Step 3: Calculate the 90th percentile score to define the high-risk threshold.
  score_threshold AS (
    SELECT
      APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS percentile_90_score
    FROM cohort_lab_scores
  ),

  -- Step 4: Identify the high-risk patients (score >= 90th percentile).
  high_risk_patients AS (
    SELECT
      c.hadm_id,
      c.hospital_expire_flag,
      DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
      s.instability_score
    FROM cohort_admissions AS c
    INNER JOIN cohort_lab_scores AS s
      ON c.hadm_id = s.hadm_id
    CROSS JOIN score_threshold
    WHERE
      s.instability_score >= score_threshold.percentile_90_score
  ),

  -- Step 5: Calculate summary statistics for the high-risk group.
  high_risk_summary AS (
    SELECT
      (SELECT percentile_90_score FROM score_threshold) AS instability_score_90th_percentile,
      COUNT(DISTINCT hadm_id) AS high_risk_patient_count,
      AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS high_risk_mortality_rate,
      AVG(los_days) AS high_risk_mean_los_days
    FROM high_risk_patients
  ),

  -- Step 6: Count frequencies of each abnormal lab for the high-risk group and for all inpatients.
  lab_frequency_comparison AS (
    SELECT
      dli.label,
      COUNTIF(
        le.hadm_id IN (SELECT hadm_id FROM high_risk_patients)
      ) AS high_risk_group_abnormal_count,
      COUNT(le.labevent_id) AS all_inpatients_abnormal_count,
      dli.itemid
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON le.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    WHERE
      le.flag = 'abnormal'
      AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR)
    GROUP BY
      dli.itemid,
      dli.label
    ORDER BY
      high_risk_group_abnormal_count DESC
    LIMIT 20 -- Limiting to the top 20 for readability
  )

-- Final Step: Combine the summary stats with the lab frequency comparison using a CROSS JOIN.
SELECT
  -- High-risk group summary stats (will be repeated on each row)
  s.instability_score_90th_percentile,
  s.high_risk_patient_count,
  s.high_risk_mortality_rate,
  s.high_risk_mean_los_days,
  -- Lab frequency comparison
  l.label AS abnormal_lab_test,
  l.high_risk_group_abnormal_count,
  l.all_inpatients_abnormal_count
FROM high_risk_summary AS s
CROSS JOIN lab_frequency_comparison AS l;