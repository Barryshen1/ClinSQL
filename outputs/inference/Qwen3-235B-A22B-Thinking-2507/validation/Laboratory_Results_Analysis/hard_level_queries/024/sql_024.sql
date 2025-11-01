WITH target_admissions AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('4275', '99801'))
          OR (d.icd_version = 10 AND d.icd_code IN ('I460', 'I461', 'I462', 'I468'))
        )
    )
),
critical_labs AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) IN (
    'potassium', 'sodium', 'chloride', 'bicarbonate', 'co2', 'total co2',
    'creatinine', 'bun', 'blood urea nitrogen', 'glucose',
    'hemoglobin', 'hgb', 'hematocrit', 'hct',
    'platelet', 'platelets',
    'wbc', 'white blood cells',
    'magnesium', 'calcium', 'phosphate',
    'inr', 'pt', 'prothrombin time', 'ptt', 'partial thromboplastin time'
  )
),
lab_abnormal AS (
  SELECT 
    le.hadm_id,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN critical_labs cl ON le.itemid = cl.itemid
  INNER JOIN target_admissions ta ON le.hadm_id = ta.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND le.charttime BETWEEN ta.admittime AND DATETIME_ADD(ta.admittime, INTERVAL 48 HOUR)
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY le.hadm_id
),
p90_value AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.9) OVER () AS p90
  FROM lab_abnormal
  LIMIT 1
),
high_group AS (
  SELECT 
    ta.hadm_id,
    ta.hospital_expire_flag,
    ta.admittime,
    ta.dischtime
  FROM target_admissions ta
  INNER JOIN lab_abnormal la ON ta.hadm_id = la.hadm_id
  CROSS JOIN p90_value p
  WHERE la.instability_score >= p.p90
),
high_group_lab_count AS (
  SELECT 
    hg.hadm_id,
    COUNT(cl.itemid) AS critical_lab_count
  FROM high_group hg
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hg.hadm_id = le.hadm_id
    AND le.charttime BETWEEN hg.admittime AND DATETIME_ADD(hg.admittime, INTERVAL 48 HOUR)
  LEFT JOIN critical_labs cl ON le.itemid = cl.itemid
  GROUP BY hg.hadm_id
),
all_inpatients AS (
  SELECT 
    hadm_id,
    admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
all_inpatients_lab_count AS (
  SELECT 
    ai.hadm_id,
    COUNT(cl.itemid) AS critical_lab_count
  FROM all_inpatients ai
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ai.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ai.admittime AND DATETIME_ADD(ai.admittime, INTERVAL 48 HOUR)
  LEFT JOIN critical_labs cl ON le.itemid = cl.itemid
  GROUP BY ai.hadm_id
)
SELECT 
  (SELECT COUNT(*) FROM high_group) AS count_high,
  (SELECT AVG(hospital_expire_flag) FROM high_group) AS mortality_high,
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) FROM high_group) AS mean_los_days_high,
  (SELECT AVG(critical_lab_count) FROM high_group_lab_count) AS critical_lab_frequency_high,
  (SELECT AVG(critical_lab_count) FROM all_inpatients_lab_count) AS critical_lab_frequency_all;