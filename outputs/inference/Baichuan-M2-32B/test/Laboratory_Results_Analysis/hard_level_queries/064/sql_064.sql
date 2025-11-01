WITH acute_pancreatitis_icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%acute pancreatitis%'
),
patients_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),
admissions_with_ap AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    pa.los
  FROM patients_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.subject_id = d.subject_id AND pa.hadm_id = d.hadm_id
  INNER JOIN acute_pancreatitis_icd_codes ap
    ON d.icd_code = ap.icd_code AND d.icd_version = ap.icd_version
),
first48_labs AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    l.flag
  FROM admissions_with_ap a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),
admission_metrics AS (
  SELECT 
    subject_id,
    hadm_id,
    hospital_expire_flag,
    los,
    COUNT(CASE WHEN flag IS NOT NULL THEN 1 END) AS instability_score,
    MAX(CASE WHEN flag = 'CRIT' THEN 1 ELSE 0 END) AS has_critical
  FROM first48_labs
  GROUP BY subject_id, hadm_id, hospital_expire_flag, los
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM admission_metrics
),
comparison_cohort AS (
  SELECT 
    COUNT(*) AS total_admissions,
    SUM(has_critical) AS total_critical,
    SUM(has_critical) * 1.0 / COUNT(*) AS crit_lab_pct
  FROM (
    SELECT 
      pa.subject_id,
      pa.hadm_id,
      MAX(CASE WHEN l.flag = 'CRIT' THEN 1 ELSE 0 END) AS has_critical
    FROM patients_admissions pa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON pa.subject_id = d.subject_id AND pa.hadm_id = d.hadm_id
      AND EXISTS (
        SELECT 1
        FROM acute_pancreatitis_icd_codes ap
        WHERE d.icd_code = ap.icd_code AND d.icd_version = ap.icd_version
      )
    WHERE NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      INNER JOIN acute_pancreatitis_icd_codes ap2
        ON d2.icd_code = ap2.icd_code AND d2.icd_version = ap2.icd_version
      WHERE d2.subject_id = pa.subject_id AND d2.hadm_id = pa.hadm_id
    )
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON pa.subject_id = l.subject_id AND pa.hadm_id = l.hadm_id
      AND l.charttime BETWEEN pa.admittime AND TIMESTAMP_ADD(pa.admittime, INTERVAL 48 HOUR)
    GROUP BY pa.subject_id, pa.hadm_id
  )
)
SELECT 
  q.quintile,
  COUNT(*) AS count,
  AVG(q.instability_score) AS mean_instability,
  AVG(q.los) AS mean_los,
  SUM(q.hospital_expire_flag) * 1.0 / COUNT(*) AS mortality,
  SUM(q.has_critical) * 1.0 / COUNT(*) AS crit_lab_pct,
  (SELECT crit_lab_pct FROM comparison_cohort) AS overall_crit_lab_pct
FROM quintiles q
GROUP BY q.quintile
ORDER BY q.quintile;