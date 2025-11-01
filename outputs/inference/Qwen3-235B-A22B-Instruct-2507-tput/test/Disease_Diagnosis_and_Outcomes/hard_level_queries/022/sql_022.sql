WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),
first_admission AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM patients_filtered p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE a.admission_type != 'AMBULATORY OBSERVATION'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
aki_ards_diagnoses AS (
  SELECT 
    di.hadm_id,
    MAX(CASE 
      WHEN (di.icd_code = 'N17' AND di.icd_version = 10) 
        OR (di.icd_code = '584' AND di.icd_version = 9) 
      THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE 
      WHEN (di.icd_code = 'J80' AND di.icd_version = 10) 
        OR (di.icd_code = '518.82' AND di.icd_version = 9) 
      THEN 1 ELSE 0 END) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  GROUP BY di.hadm_id
),
comorbidity_count AS (
  SELECT 
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE NOT (
    (di.icd_code = 'N17' AND di.icd_version = 10) OR
    (di.icd_code = '584' AND di.icd_version = 9) OR
    (di.icd_code = 'J80' AND di.icd_version = 10) OR
    (di.icd_code = '518.82' AND di.icd_version = 9)
  )
  GROUP BY di.hadm_id
),
patient_risk AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    fa.los_days,
    fa.hospital_expire_flag,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,
    COALESCE(ad.has_ards, 0) AS has_ards,
    COALESCE(ad.has_aki, 0) AS has_aki,
    5 * COALESCE(cc.comorbidity_count, 0) + 
    CASE WHEN COALESCE(ad.has_ards, 0) = 1 THEN 50 ELSE 0 END AS risk_score
  FROM first_admission fa
  LEFT JOIN comorbidity_count cc ON fa.hadm_id = cc.hadm_id
  LEFT JOIN aki_ards_diagnoses ad ON fa.hadm_id = ad.hadm_id
),
aki_patients AS (
  SELECT *
  FROM patient_risk
  WHERE has_aki = 1
),
quintiles AS (
  SELECT
    ap.*,
    NTILE(5) OVER (ORDER BY ap.risk_score) AS risk_quintile
  FROM aki_patients ap
),
mortality_and_los AS (
  SELECT
    q.risk_quintile,
    q.subject_id,
    q.hadm_id,
    q.los_days,
    q.has_ards,
    -- 30-day post-discharge mortality: dod within 30 days of dischtime
    CASE 
      WHEN p.dod IS NOT NULL 
       AND p.dod >= q.dischtime 
       AND p.dod <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
      THEN 1 ELSE 0 
    END AS died_within_30d,
    -- Survival beyond 30 days post-discharge
    CASE 
      WHEN p.dod IS NULL OR p.dod > DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
      THEN 1 ELSE 0 
    END AS survived_30d
  FROM quintiles q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON q.subject_id = p.subject_id
)
SELECT
  risk_quintile,
  COUNT(*) AS N,
  ROUND(100 * AVG(CAST(died_within_30d AS FLOAT64)), 2) AS mortality_30d_pct,
  ROUND(100 * AVG(CAST(has_ards AS FLOAT64)), 2) AS ards_cooccurrence_pct,
  APPROX_QUANTILES(CASE WHEN survived_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_survivor_los_days
FROM mortality_and_los
GROUP BY risk_quintile
ORDER BY risk_quintile;