WITH hepatic_failure_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(long_title, r'(?i)hepatic failure')
),
cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN hepatic_failure_codes hfc
    ON d.icd_code = hfc.icd_code AND d.icd_version = hfc.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),
cohort_vitals AS (
  SELECT c.subject_id, c.hadm_id,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS hr,
    MAX(CASE WHEN ce.itemid = 220179 THEN ce.valuenum END) AS sbp
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.hadm_id = ce.hadm_id
  WHERE ce.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND ce.itemid IN (220045, 220179)
    AND ce.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
  HAVING hr IS NOT NULL AND sbp IS NOT NULL
),
cohort_shock_index AS (
  SELECT subject_id, hadm_id, hr/sbp AS shock_index
  FROM cohort_vitals
),
cohort_labs AS (
  SELECT c.subject_id, c.hadm_id,
    SUM(CASE WHEN le.itemid = 50813 THEN 1 ELSE 0 END) AS lactate_count,
    SUM(CASE WHEN le.itemid = 51237 THEN 1 ELSE 0 END) AS inr_count,
    SUM(CASE WHEN le.itemid = 50885 THEN 1 ELSE 0 END) AS bilirubin_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
      AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
      AND le.itemid IN (50813, 51237, 50885)
  GROUP BY c.subject_id, c.hadm_id
),
cohort_metrics AS (
  SELECT 
    'Hepatic Failure' AS cohort_type,
    COUNT(DISTINCT c.hadm_id) AS n_patients,
    MAX(cs.shock_index) AS max_shock_index,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(c.dischtime, c.admittime, DAY)) AS avg_los,
    AVG(cl.lactate_count) AS avg_lactate_count,
    AVG(cl.inr_count) AS avg_inr_count,
    AVG(cl.bilirubin_count) AS avg_bilirubin_count
  FROM cohort c
  LEFT JOIN cohort_shock_index cs ON c.hadm_id = cs.hadm_id
  LEFT JOIN cohort_labs cl ON c.hadm_id = cl.hadm_id
),
control_group AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN hepatic_failure_codes hfc
        ON d.icd_code = hfc.icd_code AND d.icd_version = hfc.icd_version
      WHERE a.hadm_id = d.hadm_id
    )
),
control_labs AS (
  SELECT cg.subject_id, cg.hadm_id,
    SUM(CASE WHEN le.itemid = 50813 THEN 1 ELSE 0 END) AS lactate_count,
    SUM(CASE WHEN le.itemid = 51237 THEN 1 ELSE 0 END) AS inr_count,
    SUM(CASE WHEN le.itemid = 50885 THEN 1 ELSE 0 END) AS bilirubin_count
  FROM control_group cg
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cg.hadm_id = le.hadm_id
      AND le.charttime BETWEEN cg.admittime AND DATETIME_ADD(cg.admittime, INTERVAL 48 HOUR)
      AND le.itemid IN (50813, 51237, 50885)
  GROUP BY cg.subject_id, cg.hadm_id
),
control_metrics AS (
  SELECT 
    'Control' AS cohort_type,
    COUNT(DISTINCT cg.hadm_id) AS n_patients,
    NULL AS max_shock_index,
    NULL AS mortality_rate,
    NULL AS avg_los,
    AVG(cl.lactate_count) AS avg_lactate_count,
    AVG(cl.inr_count) AS avg_inr_count,
    AVG(cl.bilirubin_count) AS avg_bilirubin_count
  FROM control_group cg
  LEFT JOIN control_labs cl ON cg.hadm_id = cl.hadm_id
)
SELECT * FROM cohort_metrics
UNION ALL
SELECT * FROM control_metrics;