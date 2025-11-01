WITH sepsis_patients AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN d.icd_code = 'R65.21' THEN 'septic_shock'
      WHEN d.icd_code = 'R65.20' THEN 'no_shock'
      ELSE NULL
    END AS sepsis_severity,
    a.hospital_expire_flag,
    a.admission_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON d.subject_id = p.subject_id
  WHERE
    d.icd_code IN ('R65.20', 'R65.21')
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
sepsis_with_max_severity AS (
  -- If a patient has both R65.20 and R65.21, assign 'septic_shock'
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN sepsis_severity = 'septic_shock' THEN 'septic_shock' ELSE 'no_shock' END) AS sepsis_severity,
    MAX(hospital_expire_flag) AS hospital_expire_flag,
    admission_type,
    los_days
  FROM
    sepsis_patients
  GROUP BY
    subject_id, hadm_id, admission_type, los_days
),
comorbidity_count AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    COUNT(*) AS comorbidity_count
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  INNER JOIN
    sepsis_with_max_severity s
    ON d.subject_id = s.subject_id AND d.hadm_id = s.hadm_id
  WHERE
    d.icd_code NOT IN ('R65.20', 'R65.21') -- exclude sepsis codes
  GROUP BY
    d.subject_id, d.hadm_id
)
SELECT
  s.sepsis_severity,
  CASE
    WHEN s.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN s.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    WHEN s.los_days >= 8 THEN '>=8 days'
    ELSE 'Unknown'
  END AS los_group,
  s.admission_type,
  ROUND(100.0 * AVG(s.hospital_expire_flag), 2) AS in_hospital_mortality_pct,
  ROUND(AVG(c.comorbidity_count), 2) AS mean_comorbidity_count
FROM
  sepsis_with_max_severity s
LEFT JOIN
  comorbidity_count c
  ON s.subject_id = c.subject_id AND s.hadm_id = c.hadm_id
GROUP BY
  s.sepsis_severity,
  CASE
    WHEN s.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN s.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    WHEN s.los_days >= 8 THEN '>=8 days'
    ELSE 'Unknown'
  END,
  s.admission_type
ORDER BY
  s.sepsis_severity,
  los_group,
  admission_type;