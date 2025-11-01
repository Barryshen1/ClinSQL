WITH initial_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 40 AND 50
),
ards_cohort AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE icd_version = 10 AND icd_code = 'J80'
),
ards_patients AS (
  SELECT ic.*
  FROM initial_cohort ic
  INNER JOIN ards_cohort ac
    ON ic.hadm_id = ac.hadm_id
),
non_ards_patients AS (
  SELECT ic.*
  FROM initial_cohort ic
  LEFT JOIN ards_cohort ac
    ON ic.hadm_id = ac.hadm_id
  WHERE ac.hadm_id IS NULL
),
ards_lab_instability AS (
  SELECT 
    ap.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM ards_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l
    ON ap.hadm_id = l.hadm_id
    AND l.charttime BETWEEN ap.admittime AND ap.admittime + INTERVAL 72 HOUR
  WHERE l.flag = 'abnormal'
  GROUP BY ap.hadm_id
),
p75_threshold AS (
  SELECT 
    COALESCE(APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)], 0) AS threshold
  FROM ards_lab_instability
),
ards_high AS (
  SELECT 
    ap.*,
    COALESCE(ali.lab_instability_score, 0) AS lab_instability_score
  FROM ards_patients ap
  LEFT JOIN ards_lab_instability ali
    ON ap.hadm_id = ali.hadm_id
  CROSS JOIN p75_threshold p
  WHERE COALESCE(ali.lab_instability_score, 0) >= p.threshold
),
non_ards_lab AS (
  SELECT 
    np.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM non_ards_patients np
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l
    ON np.hadm_id = l.hadm_id
    AND l.charttime BETWEEN np.admittime AND np.admittime + INTERVAL 72 HOUR
  WHERE l.flag = 'abnormal'
  GROUP BY np.hadm_id
),
non_ards_avg AS (
  SELECT 
    AVG(critical_lab_count) AS avg_critical_labs
  FROM non_ards_lab
)
SELECT 
  (SELECT AVG(hospital_expire_flag) FROM ards_high) AS mortality_rate,
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) FROM ards_high) AS mean_los_days,
  (SELECT AVG(lab_instability_score) FROM ards_high) AS ards_high_avg_critical_labs,
  (SELECT avg_critical_labs FROM non_ards_avg) AS non_ards_avg_critical_labs;