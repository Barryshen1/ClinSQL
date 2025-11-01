WITH lower_gi_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'lower.*(gi|gastrointestinal).*(bleed|hemorrhage)') OR
    REGEXP_CONTAINS(LOWER(long_title), r'rectal (bleed|hemorrhage)') OR
    REGEXP_CONTAINS(LOWER(long_title), r'blood in stool') OR
    REGEXP_CONTAINS(LOWER(long_title), r'hematochezia')
),
complication_codes AS (
  SELECT 'AKI' AS category, 9 AS icd_version, '584%' AS pattern
  UNION ALL SELECT 'AKI', 10, 'N17%'
  UNION ALL SELECT 'Shock', 9, '7855'
  UNION ALL SELECT 'Shock', 10, 'R57%'
  UNION ALL SELECT 'MI', 9, '410%'
  UNION ALL SELECT 'MI', 10, 'I21%'
  UNION ALL SELECT 'MI', 10, 'I22%'
  UNION ALL SELECT 'Stroke', 9, '433%'
  UNION ALL SELECT 'Stroke', 9, '434%'
  UNION ALL SELECT 'Stroke', 9, '436%'
  UNION ALL SELECT 'Stroke', 10, 'I63%'
  UNION ALL SELECT 'Stroke', 10, 'I64%'
  UNION ALL SELECT 'Respiratory failure', 9, '51881'
  UNION ALL SELECT 'Respiratory failure', 9, '51882'
  UNION ALL SELECT 'Respiratory failure', 9, '51884'
  UNION ALL SELECT 'Respiratory failure', 9, '51885'
  UNION ALL SELECT 'Respiratory failure', 10, 'J960'
  UNION ALL SELECT 'Respiratory failure', 10, 'J962'
  UNION ALL SELECT 'Respiratory failure', 10, 'J80'
),
cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.dod,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND d.seq_num = 1
    AND d.icd_code IN (SELECT icd_code FROM lower_gi_codes WHERE icd_version = d.icd_version)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
),
complications AS (
  SELECT 
    c.hadm_id,
    cc.category
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  INNER JOIN complication_codes cc
    ON d.icd_version = cc.icd_version 
    AND (
      (cc.icd_version = 9 AND d.icd_code LIKE cc.pattern) OR
      (cc.icd_version = 10 AND d.icd_code LIKE cc.pattern)
    )
  WHERE d.seq_num > 1
  GROUP BY c.hadm_id, cc.category
),
risk_scores AS (
  SELECT 
    c.*,
    COUNT(DISTINCT comp.category) AS risk_score
  FROM cohort c
  LEFT JOIN complications comp
    ON c.hadm_id = comp.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.gender, c.dod, c.age
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score, hadm_id) AS quintile
  FROM risk_scores
),
outcomes AS (
  SELECT 
    quintile,
    COUNT(*) AS n,
    AVG(
      CASE WHEN dod IS NOT NULL AND dod <= DATE_ADD(DATE(admittime), INTERVAL 90 DAY) 
        THEN 1 ELSE 0 END
    ) AS mortality_90d,
    AVG(CASE WHEN risk_score >= 1 THEN 1 ELSE 0 END) AS major_complication_rate
  FROM quintiles
  GROUP BY quintile
),
survivors_los AS (
  SELECT 
    quintile,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM quintiles
  WHERE 
    dod IS NULL OR dod > DATE_ADD(DATE(admittime), INTERVAL 90 DAY)
),
median_los AS (
  SELECT 
    quintile,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
  FROM survivors_los
  GROUP BY quintile
)
SELECT 
  o.quintile,
  o.n,
  o.mortality_90d,
  o.major_complication_rate,
  m.median_los
FROM outcomes o
LEFT JOIN median_los m
  ON o.quintile = m.quintile
ORDER BY o.quintile;