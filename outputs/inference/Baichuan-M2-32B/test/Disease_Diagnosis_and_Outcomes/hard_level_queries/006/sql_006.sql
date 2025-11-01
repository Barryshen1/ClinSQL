WITH patient_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.dod,
    p.gender,
    DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date,
    TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) BETWEEN 70 AND 80
),
lower_gi_bleed_admissions AS (
  SELECT DISTINCT
    hadm_id,
    subject_id
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON pa.hadm_id = d.hadm_id AND pa.subject_id = d.subject_id
  WHERE d.icd_version = 10
    AND d.icd_code IN ('K52.2', 'K52.3', 'K52.8', 'K52.9')
),
complications AS (
  SELECT 
    d.hadm_id,
    d.subject_id,
    COUNT(DISTINCT 
      CASE 
        WHEN d.icd_code IN ('N17.0','N17.1','N17.2','N17.3','N17.4','N17.5','N17.6','N17.7','N17.8','N17.9') THEN 'AKI'
        WHEN d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'A42%' OR d.icd_code LIKE 'A43%' OR d.icd_code LIKE 'A44%' OR d.icd_code LIKE 'A45%' OR d.icd_code LIKE 'A46%' OR d.icd_code LIKE 'A47%' OR d.icd_code LIKE 'A48%' OR d.icd_code LIKE 'A49%' THEN 'sepsis'
        WHEN d.icd_code IN ('J18.0','J18.1','J18.2','J18.3','J18.4','J18.5','J18.6','J18.7','J18.8','J18.9') THEN 'pneumonia'
      END
    ) AS num_complications
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
    AND (
      d.icd_code IN ('N17.0','N17.1','N17.2','N17.3','N17.4','N17.5','N17.6','N17.7','N17.8','N17.9')
      OR d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'A42%' OR d.icd_code LIKE 'A43%' OR d.icd_code LIKE 'A44%' OR d.icd_code LIKE 'A45%' OR d.icd_code LIKE 'A46%' OR d.icd_code LIKE 'A47%' OR d.icd_code LIKE 'A48%' OR d.icd_code LIKE 'A49%'
      OR d.icd_code IN ('J18.0','J18.1','J18.2','J18.3','J18.4','J18.5','J18.6','J18.7','J18.8','J18.9')
    )
  GROUP BY d.hadm_id, d.subject_id
),
major_surgeries AS (
  SELECT 
    p.hadm_id,
    p.subject_id,
    COUNT(DISTINCT p.icd_code) AS num_major_surgeries
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE p.icd_version = 10
    AND LEFT(p.icd_code, 1) BETWEEN '0' AND '9'
  GROUP BY p.hadm_id, p.subject_id
),
risk_scores AS (
  SELECT 
    l.hadm_id,
    l.subject_id,
    l.age_at_admission,
    COALESCE(c.num_complications, 0) AS num_complications,
    COALESCE(m.num_major_surgeries, 0) AS num_major_surgeries,
    COALESCE(c.num_complications, 0) + COALESCE(m.num_major_surgeries, 0) + (l.age_at_admission - 70) AS risk_score
  FROM lower_gi_bleed_admissions l
  LEFT JOIN complications c ON l.hadm_id = c.hadm_id AND l.subject_id = c.subject_id
  LEFT JOIN major_surgeries m ON l.hadm_id = m.hadm_id AND l.subject_id = m.subject_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM risk_scores
),
outcomes AS (
  SELECT 
    q.hadm_id,
    q.subject_id,
    q.quintile,
    q.risk_score,
    q.age_at_admission,
    pa.dod,
    pa.admittime,
    pa.dischtime,
    -- 90-day mortality: death within 90 days of admission
    CASE WHEN pa.dod IS NOT NULL AND TIMESTAMP_DIFF(pa.dod, pa.admittime, DAY) <= 90 THEN 1 ELSE 0 END AS death_within_90_days,
    -- Major complication: at least one complication (AKI, sepsis, or pneumonia)
    CASE WHEN COALESCE(q.num_complications, 0) > 0 THEN 1 ELSE 0 END AS has_complication,
    TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days
  FROM quintiles q
  INNER JOIN patient_admissions pa ON q.hadm_id = pa.hadm_id AND q.subject_id = pa.subject_id
),
final AS (
  SELECT 
    quintile,
    COUNT(*) AS N,
    AVG(death_within_90_days) AS mortality_rate,
    AVG(has_complication) AS complication_rate,
    (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) 
     FROM outcomes o2 
     WHERE o2.quintile = o1.quintile AND o2.death_within_90_days = 0) AS median_los_survivors
  FROM outcomes o1
  GROUP BY quintile
)
SELECT * FROM final
ORDER BY quintile;