WITH
  -- Step 1: Identify ARDS patients (male, age 71-81 at admission) with ICU stays
  ards_patients AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 71 AND 81
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.subject_id = a.subject_id
          AND d.hadm_id = a.hadm_id
          AND d.icd_code LIKE 'J80.1%'
      )
  ),
  -- Step 2: Get first ICU stay per admission for ARDS patients
  ards_icu_stays AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) AS rn
    FROM
      ards_patients a
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.subject_id = i.subject_id
      AND a.hadm_id = i.hadm_id
    WHERE
      i.intime >= a.admittime
    QUALIFY rn = 1
  ),
  -- Step 3: Get vital signs itemids for instability score
  vital_signs AS (
    SELECT
      itemid,
      category
    FROM
      `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE
      category IN ('Heart rate', 'Blood pressure systolic', 'Temperature', 'Respiratory rate', 'O2 saturation')
  ),
  -- Step 4: Compute abnormal vital signs in first 72 hours of ICU stay
  ards_vitals AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      c.stay_id,
      c.charttime,
      CASE
        WHEN v.category = 'Heart rate' AND (c.valuenum < 40 OR c.valuenum > 130) THEN 1
        WHEN v.category = 'Blood pressure systolic' AND (c.valuenum < 90 OR c.valuenum > 180) THEN 1
        WHEN v.category = 'Temperature' AND (c.valuenum < 35 OR c.valuenum > 39) THEN 1
        WHEN v.category = 'Respiratory rate' AND (c.valuenum < 8 OR c.valuenum > 35) THEN 1
        WHEN v.category = 'O2 saturation' AND c.valuenum < 90 THEN 1
        ELSE 0
      END AS abnormal
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` c
    INNER JOIN
      vital_signs v
      ON c.itemid = v.itemid
    INNER JOIN
      ards_icu_stays i
      ON c.subject_id = i.subject_id
      AND c.hadm_id = i.hadm_id
      AND c.stay_id = i.stay_id
    WHERE
      c.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
      AND c.valuenum IS NOT NULL
  ),
  -- Step 5: Compute instability score per ICU stay
  instability_scores AS (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      SUM(abnormal) AS instability_score
    FROM
      ards_vitals
    GROUP BY
      subject_id, hadm_id, stay_id
  ),
  -- Step 6: Compute 90th percentile of instability score
  percentile AS (
    SELECT
      APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90
    FROM
      instability_scores
  ),
  -- Step 7: Get high instability patients (score >= p90) with admission details
  high_instability AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      a.age_at_admission,
      a.hospital_expire_flag,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM
      instability_scores s
    INNER JOIN
      ards_icu_stays i
      ON s.subject_id = i.subject_id
      AND s.hadm_id = i.hadm_id
      AND s.stay_id = i.stay_id
    INNER JOIN
      ards_patients a
      ON i.subject_id = a.subject_id
      AND i.hadm_id = a.hadm_id
    CROSS JOIN
      percentile p
    WHERE
      s.instability_score >= p.p90
  ),
  -- Step 8: Define critical labs and their itemids
  critical_labs AS (
    SELECT
      itemid
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
      label IN ('Creatinine', 'Sodium', 'Potassium', 'Hemoglobin', 'White blood cell count')
  ),
  -- Step 9: Compute critical lab flags for high instability group in first 72h of hospitalization
  high_instability_labs AS (
    SELECT
      l.subject_id,
      l.hadm_id,
      MAX(CASE
          WHEN lab.label = 'Creatinine' AND l.valuenum > 2.0 THEN 1
          WHEN lab.label = 'Sodium' AND (l.valuenum < 130 OR l.valuenum > 150) THEN 1
          WHEN lab.label = 'Potassium' AND (l.valuenum < 3.5 OR l.valuenum > 5.5) THEN 1
          WHEN lab.label = 'Hemoglobin' AND (l.valuenum < 7 OR l.valuenum > 20) THEN 1
          WHEN lab.label = 'White blood cell count' AND (l.valuenum < 2 OR l.valuenum > 30) THEN 1
          ELSE 0
        END) AS has_critical_lab
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN
      critical_labs cl
      ON l.itemid = cl.itemid
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_labitems` lab
      ON l.itemid = lab.itemid
    INNER JOIN
      high_instability h
      ON l.subject_id = h.subject_id
      AND l.hadm_id = h.hadm_id
    WHERE
      l.charttime BETWEEN h.admittime AND DATETIME_ADD(h.admittime, INTERVAL 72 HOUR)
      AND l.valuenum IS NOT NULL
    GROUP BY
      l.subject_id, l.hadm_id
  ),
  -- Step 10: Aggregate high instability group metrics
  high_instability_summary AS (
    SELECT
      COUNT(*) AS num_patients,
      SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate,
      AVG(los_days) AS mean_los,
      SUM(has_critical_lab) / COUNT(*) AS critical_lab_rate
    FROM
      high_instability h
    LEFT JOIN
      high_instability_labs f
      ON h.subject_id = f.subject_id
      AND h.hadm_id = f.hadm_id
  ),
  -- Step 11: Get control group (general inpatients: male, age 71-81, without ARDS) with random sampling
  control_patients AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 71 AND 81
      AND NOT EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.subject_id = a.subject_id
          AND d.hadm_id = a.hadm_id
          AND d.icd_code LIKE 'J80.1%'
      )
    TABLESAMPLE SYSTEM (10 PERCENT)
  ),
  -- Step 12: Compute critical lab flags for control group in first 72h
  control_labs AS (
    SELECT
      l.subject_id,
      l.hadm_id,
      MAX(CASE
          WHEN lab.label = 'Creatinine' AND l.valuenum > 2.0 THEN 1
          WHEN lab.label = 'Sodium' AND (l.valuenum < 130 OR l.valuenum > 150) THEN 1
          WHEN lab.label = 'Potassium' AND (l.valuenum < 3.5 OR l.valuenum > 5.5) THEN 1
          WHEN lab.label = 'Hemoglobin' AND (l.valuenum < 7 OR l.valuenum > 20) THEN 1
          WHEN lab.label = 'White blood cell count' AND (l.valuenum < 2 OR l.valuenum > 30) THEN 1
          ELSE 0
        END) AS has_critical_lab
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN
      critical_labs cl
      ON l.itemid = cl.itemid
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_labitems` lab
      ON l.itemid = lab.itemid
    INNER JOIN
      control_patients c
      ON l.subject_id = c.subject_id
      AND l.hadm_id = c.hadm_id
    WHERE
      l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
      AND l.valuenum IS NOT NULL
    GROUP BY
      l.subject_id, l.hadm_id
  ),
  control_summary AS (
    SELECT
      COUNT(*) AS num_patients,
      SUM(has_critical_lab) / COUNT(*) AS critical_lab_rate
    FROM
      control_patients c
    LEFT JOIN
      control_labs f
      ON c.subject_id = f.subject_id
      AND c.hadm_id = f.hadm_id
  )
-- Final output
SELECT
  p.p90 AS instability_score_90th_percentile,
  h.num_patients AS high_instability_patients,
  h.mortality_rate,
  h.mean_los,
  h.critical_lab_rate AS high_instability_critical_lab_rate,
  c.critical_lab_rate AS control_critical_lab_rate,
  (h.critical_lab_rate - c.critical_lab_rate) AS difference,
  (h.critical_lab_rate / c.critical_lab_rate) AS ratio
FROM
  percentile p
CROSS JOIN
  high_instability_summary h
CROSS JOIN
  control_summary c;