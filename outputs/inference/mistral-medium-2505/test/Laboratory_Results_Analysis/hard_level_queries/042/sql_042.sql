WITH
-- Get male patients aged 73-83 with ICH
ich_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age BETWEEN 73 AND 83 OR
         (p.anchor_year IS NOT NULL AND
          (EXTRACT(YEAR FROM CURRENT_DATE()) - p.anchor_year) BETWEEN 73 AND 83))
    AND (d.icd_code LIKE '431.%' OR d.icd_code LIKE 'I61.%')
),

-- Get all male inpatients for comparison
all_male_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
),

-- Calculate LOS for each admission
los_calc AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Get abnormal labs within 48 hours of admission for ICH patients
abnormal_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    d.category AS lab_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN
    ich_patients i ON l.subject_id = i.subject_id AND l.hadm_id = i.hadm_id
  WHERE
    l.charttime BETWEEN i.admittime AND TIMESTAMP_ADD(i.admittime, INTERVAL 48 HOUR)
    AND (
      (l.valuenum < l.ref_range_lower AND l.ref_range_lower IS NOT NULL) OR
      (l.valuenum > l.ref_range_upper AND l.ref_range_upper IS NOT NULL)
    )
    AND l.valuenum IS NOT NULL
),

-- Count distinct abnormal lab categories per patient
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT lab_category) AS instability_score
  FROM
    abnormal_labs
  GROUP BY
    subject_id, hadm_id
),

-- Calculate quartiles for instability scores
quartiles AS (
  SELECT
    instability_score,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM
    instability_scores
),

-- Join all data for ICH patients
ich_results AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.hospital_expire_flag,
    i.dod,
    l.los_days,
    s.instability_score,
    q.quartile
  FROM
    ich_patients i
  JOIN
    los_calc l ON i.hadm_id = l.hadm_id
  LEFT JOIN
    instability_scores s ON i.subject_id = s.subject_id AND i.hadm_id = s.hadm_id
  LEFT JOIN
    quartiles q ON s.instability_score = q.instability_score
),

-- Calculate metrics for ICH patients by quartile
ich_metrics AS (
  SELECT
    quartile,
    COUNT(*) AS patient_count,
    AVG(los_days) AS avg_los,
    SUM(CASE WHEN hospital_expire_flag = 1 OR dod IS NOT NULL THEN 1 ELSE 0 END) AS deaths,
    SUM(CASE WHEN hospital_expire_flag = 1 OR dod IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM
    ich_results
  GROUP BY
    quartile
),

-- Calculate metrics for all male inpatients
all_male_metrics AS (
  SELECT
    COUNT(*) AS total_patients,
    AVG(l.los_days) AS avg_los_all,
    SUM(CASE WHEN a.hospital_expire_flag = 1 OR p.dod IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate_all
  FROM
    all_male_inpatients a
  JOIN
    los_calc l ON a.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
)

-- Final results
SELECT
  q.quartile,
  q.patient_count,
  q.avg_los,
  m.avg_los_all,
  q.mortality_rate,
  m.mortality_rate_all
FROM
  ich_metrics q
CROSS JOIN
  all_male_metrics m
ORDER BY
  q.quartile;