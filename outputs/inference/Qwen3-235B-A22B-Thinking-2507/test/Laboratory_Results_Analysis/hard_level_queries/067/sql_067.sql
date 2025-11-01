WITH patients_age AS (
  SELECT 
    subject_id,
    EXTRACT(YEAR FROM admittime) - anchor_year + anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` USING (subject_id)
),
acs_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (60 * 60 * 24) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_age pa ON a.subject_id = pa.subject_id
  WHERE 
    pa.age_at_admission BETWEEN 53 AND 63
    AND a.hospital_expire_flag IS NOT NULL
    AND a.subject_id IN (
      SELECT subject_id 
      FROM `physionet-data.mimiciv_3_1_hosp.patients` 
      WHERE gender = 'F'
    )
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_version = 10 
        AND (icd_code LIKE 'I20%' OR icd_code LIKE 'I21%' OR icd_code LIKE 'I22%')
    )
),
labs_72h AS (
  SELECT 
    l.hadm_id,
    MAX(CASE WHEN d.label = 'Potassium' AND (l.valuenum < 3.0 OR l.valuenum > 6.0) THEN 1 ELSE 0 END) AS has_critical_k,
    MAX(CASE WHEN d.label = 'Sodium' AND (l.valuenum < 120 OR l.valuenum > 160) THEN 1 ELSE 0 END) AS has_critical_na,
    MAX(CASE WHEN d.label = 'Glucose' AND (l.valuenum < 40 OR l.valuenum > 600) THEN 1 ELSE 0 END) AS has_critical_glucose,
    MAX(CASE WHEN d.label = 'Creatinine' AND l.valuenum > 3.0 THEN 1 ELSE 0 END) AS has_critical_creat,
    MAX(CASE WHEN d.label = 'BUN' AND l.valuenum > 60 THEN 1 ELSE 0 END) AS has_critical_bun
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  INNER JOIN acs_cohort a ON l.hadm_id = a.hadm_id
  WHERE 
    l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND d.label IN ('Potassium', 'Sodium', 'Glucose', 'Creatinine', 'BUN')
    AND l.valuenum IS NOT NULL
  GROUP BY l.hadm_id
),
instability AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    a.los_days,
    COALESCE(has_critical_k, 0) + 
    COALESCE(has_critical_na, 0) + 
    COALESCE(has_critical_glucose, 0) + 
    COALESCE(has_critical_creat, 0) + 
    COALESCE(has_critical_bun, 0) AS instability_score
  FROM acs_cohort a
  LEFT JOIN labs_72h l ON a.hadm_id = l.hadm_id
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM instability
)
SELECT 
  quartile,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  AVG(los_days) AS avg_los_days
FROM quartiles
GROUP BY quartile
ORDER BY quartile;