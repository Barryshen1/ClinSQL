WITH eligible_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    -- Calculate birth year and age at admission
    (p.anchor_year - p.anchor_age) AS birth_year,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 51 AND 61
),
surgical_admissions AS (
  SELECT DISTINCT e.subject_id, e.hadm_id
  FROM eligible_admissions e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
    ON e.hadm_id = pi.hadm_id
  WHERE REGEXP_CONTAINS(pi.icd_code, r'^[0-6][0-9]')   -- Note: This regex may not be appropriate for ICD-9-CM; consider using BETWEEN '00000' AND '69999' if needed
),
high_risk_drugs AS (
  SELECT drug, weight
  FROM UNNEST([
    STRUCT('warfarin' AS drug, 2 AS weight),
    STRUCT('heparin', 2),
    STRUCT('enoxaparin', 2),
    STRUCT('insulin', 2),
    STRUCT('morphine', 2),
    STRUCT('fentanyl', 2),
    STRUCT('aspirin', 1)   -- Example non-high-risk
  ]) 
),
admission_prescriptions AS (
  SELECT 
    p.hadm_id,
    p.drug,
    p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN surgical_admissions sa 
    ON p.hadm_id = sa.hadm_id
  WHERE p.starttime BETWEEN sa.admittime AND TIMESTAMP_ADD(sa.admittime, INTERVAL 24 HOUR)
),
admission_complexity AS (
  SELECT 
    ap.hadm_id,
    COUNT(DISTINCT ap.drug) AS unique_drugs,
    COALESCE(SUM(hr.weight), 0) AS total_weight,
    COUNT(DISTINCT ap.drug) + COALESCE(SUM(hr.weight), 0) AS complexity
  FROM admission_prescriptions ap
  LEFT JOIN high_risk_drugs hr 
    ON LOWER(ap.drug) = LOWER(hr.drug)   -- Exact match; consider using LIKE for partial matches if needed
  GROUP BY ap.hadm_id
),
complexity_quartiles AS (
  SELECT 
    hadm_id,
    complexity,
    NTILE(4) OVER (ORDER BY complexity) AS quartile
  FROM admission_complexity
),
outcomes AS (
  SELECT 
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag,
    -- Check for 30-day readmission: at least one readmission within 30 days
    (SELECT COUNT(*) > 0 
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
     WHERE a2.subject_id = a.subject_id
       AND a2.admittime > a.dischtime
       AND a2.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
    ) AS readmitted
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN surgical_admissions sa 
    ON a.hadm_id = sa.hadm_id
),
final_data AS (
  SELECT 
    cq.quartile,
    COUNT(*) AS count,
    AVG(o.los) AS avg_los,
    SUM(CAST(o.hospital_expire_flag AS INT)) / COUNT(*) * 100 AS mortality_percent,
    SUM(CAST(o.readmitted AS INT)) / COUNT(*) * 100 AS readmission_percent
  FROM complexity_quartiles cq
  INNER JOIN outcomes o 
    ON cq.hadm_id = o.hadm_id
  GROUP BY cq.quartile
  ORDER BY cq.quartile
)
SELECT * FROM final_data;