WITH high_risk_drugs AS (
  SELECT 'Warfarin' AS drug
  UNION ALL SELECT 'Insulin'
  UNION ALL SELECT 'Digoxin'
  -- Placeholder list; in practice replace with clinical criteria
),
base_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN ('I46.0', 'I46.1', 'I46.2', 'I46.8', 'I46.9')
    )
),
medication_scores AS (
  SELECT 
    b.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drugs,
    COUNT(DISTINCT CASE WHEN pr.drug IN (SELECT drug FROM high_risk_drugs) THEN pr.drug END) AS high_risk_count,
    COUNT(DISTINCT pr.route) AS routes,
    COUNT(DISTINCT pr.drug) + 2 * COUNT(DISTINCT CASE WHEN pr.drug IN (SELECT drug FROM high_risk_drugs) THEN pr.drug END) + COUNT(DISTINCT pr.route) AS score
  FROM base_admissions b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON b.hadm_id = pr.hadm_id
    AND pr.starttime >= b.admittime
    AND pr.starttime < TIMESTAMP_ADD(b.admittime, INTERVAL 7 DAY)
  GROUP BY b.hadm_id
),
readmission_flag AS (
  SELECT 
    b.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = b.subject_id
          AND a2.admittime > b.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(b.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM base_admissions b
),
combined AS (
  SELECT 
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    m.score,
    r.readmitted_30d,
    TIMESTAMP_DIFF(b.dischtime, b.admittime, SECOND) / (24*60*60.0) AS los_days
  FROM base_admissions b
  LEFT JOIN medication_scores m ON b.hadm_id = m.hadm_id
  LEFT JOIN readmission_flag r ON b.hadm_id = r.hadm_id
),
with_tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY score) AS tertile_group
  FROM combined
)
SELECT 
  tertile_group,
  COUNT(*) AS count,
  MIN(score) AS min_score,
  MAX(score) AS max_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmitted_30d) * 100 AS readmission_pct
FROM with_tertiles
GROUP BY tertile_group
ORDER BY tertile_group;