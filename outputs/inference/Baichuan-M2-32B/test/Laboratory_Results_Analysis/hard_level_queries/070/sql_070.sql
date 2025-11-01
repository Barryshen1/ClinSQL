WITH
  -- Step 1: Identify male patients aged 40-50 at admission
  patients_40_50_male AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_year,
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      -- Calculate birth year: anchor_year - anchor_age
      p.anchor_year - p.anchor_age AS birth_year,
      -- Calculate age at admission: EXTRACT(YEAR FROM admittime) - birth_year
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 40 AND 50
  ),
  -- Step 2: Filter for hemorrhagic stroke admissions using ICD codes
  hemorrhagic_stroke_admissions AS (
    SELECT
      h.*
    FROM
      patients_40_50_male h
    JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON h.hadm_id = d.hadm_id
    WHERE
      (d.icd_version = 9 AND d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR d.icd_code LIKE '433%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%')
    GROUP BY
      h.subject_id, h.hadm_id, h.admittime, h.dischtime, h.hospital_expire_flag, h.age_at_admission, h.gender  -- Added h.gender to GROUP BY
  ),
  -- Step 3: Create control group (all male 40-50 admissions excluding stroke patients)
  control_admissions AS (
    SELECT
      h.*
    FROM
      patients_40_50_male h
    LEFT JOIN
      hemorrhagic_stroke_admissions s
      ON h.hadm_id = s.hadm_id
    WHERE
      s.hadm_id IS NULL  -- Exclude stroke admissions
  ),
  -- Step 4: Get labevents within 72 hours of admission for both cohorts
  labevents_72h AS (
    SELECT
      a.hadm_id,
      a.admittime,  -- Added to fix missing admittime in subquery
      le.subject_id,
      le.itemid,
      le.charttime,
      le.valuenum,
      le.valueuom,
      le.ref_range_lower,
      le.ref_range_upper,
      le.flag
    FROM
      (SELECT hadm_id, admittime FROM hemorrhagic_stroke_admissions  -- Include admittime
       UNION ALL
       SELECT hadm_id, admittime FROM control_admissions) a
    JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.hadm_id = le.hadm_id
    WHERE
      le.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
      AND le.valuenum IS NOT NULL  -- Focus on numeric labs
  ),
  -- Step 5: Identify abnormal labs (using ref_range or flag)
  abnormal_labs AS (
    SELECT
      hadm_id,
      itemid,
      -- Abnormal if outside ref_range or flagged as H/L
      CASE
        WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NOT NULL THEN
          (valuenum < ref_range_lower OR valuenum > ref_range_upper)
        WHEN flag IN ('H', 'L') THEN TRUE
        ELSE FALSE
      END AS is_abnormal
    FROM
      labevents_72h
  ),
  -- Step 6: Count unique abnormal labs per admission for stroke cohort
  unique_abnormal_labs_per_admission AS (
    SELECT
      hadm_id,
      COUNT(DISTINCT IF(is_abnormal, itemid, NULL)) AS instability_score
    FROM
      abnormal_labs
    WHERE
      hadm_id IN (SELECT hadm_id FROM hemorrhagic_stroke_admissions)
    GROUP BY
      hadm_id
  ),
  -- Step 7: Assign quartiles to stroke cohort based on instability_score
  stroke_cohort_quartiles AS (
    SELECT
      s.*,
      u.instability_score,
      NTILE(4) OVER (ORDER BY u.instability_score) AS quartile
    FROM
      hemorrhagic_stroke_admissions s
    LEFT JOIN
      unique_abnormal_labs_per_admission u
      ON s.hadm_id = u.hadm_id
  ),
  -- Step 8: Compute metrics for stroke quartiles (LOS, mortality)
  stroke_quartile_metrics AS (
    SELECT
      quartile,
      AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
      NULL AS itemid,
      NULL AS abnormal_rate
    FROM
      stroke_cohort_quartiles
    GROUP BY
      quartile
  ),
  -- Step 9: Compute per-lab abnormal rates for each stroke quartile
  stroke_lab_rates AS (
    SELECT
      q.quartile,
      a.itemid,
      COUNT(DISTINCT IF(ab.is_abnormal, q.hadm_id, NULL)) * 1.0 / COUNT(DISTINCT q.hadm_id) AS abnormal_rate,
      NULL AS avg_los,
      NULL AS mortality_rate
    FROM
      stroke_cohort_quartiles q
    JOIN
      abnormal_labs ab
      ON q.hadm_id = ab.hadm_id
    GROUP BY
      q.quartile, a.itemid
  ),
  -- Step 10: Compute overall metrics for control group (LOS, mortality)
  control_metrics AS (
    SELECT
      NULL AS quartile,
      AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
      NULL AS itemid,
      NULL AS abnormal_rate
  ),
  -- Step 11: Compute per-lab abnormal rates for control group
  control_lab_rates AS (
    SELECT
      NULL AS quartile,
      itemid,
      COUNT(DISTINCT IF(is_abnormal, hadm_id, NULL)) * 1.0 / COUNT(DISTINCT hadm_id) AS abnormal_rate,
      NULL AS avg_los,
      NULL AS mortality_rate
    FROM
      abnormal_labs
    WHERE
      hadm_id IN (SELECT hadm_id FROM control_admissions)
    GROUP BY
      itemid
  ),
  -- Step 12: Combine all results with group_type
  final_results AS (
    SELECT
      'stroke_quartile' AS group_type,
      quartile,
      NULL AS itemid,
      avg_los,
      mortality_rate,
      NULL AS abnormal_rate
    FROM
      stroke_quartile_metrics
    UNION ALL
    SELECT
      'stroke_lab' AS group_type,
      quartile,
      itemid,
      NULL AS avg_los,
      NULL AS mortality_rate,
      abnormal_rate
    FROM
      stroke_lab_rates
    UNION ALL
    SELECT
      'control_overall' AS group_type,
      NULL AS quartile,
      NULL AS itemid,
      avg_los,
      mortality_rate,
      NULL AS abnormal_rate
    FROM
      control_metrics
    UNION ALL
    SELECT
      'control_lab' AS group_type,
      NULL AS quartile,
      itemid,
      NULL AS avg_los,
      NULL AS mortality_rate,
      abnormal_rate
    FROM
      control_lab_rates
  )
SELECT
  group_type,
  quartile,
  itemid,
  avg_los,
  mortality_rate,
  abnormal_rate
FROM
  final_results
ORDER BY
  group_type, quartile, itemid;