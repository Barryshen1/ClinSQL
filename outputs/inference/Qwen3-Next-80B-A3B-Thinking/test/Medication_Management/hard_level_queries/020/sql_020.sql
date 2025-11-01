WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND d.icd_code LIKE 'I46%'
    )
),

medication_scores AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_drugs,
    COUNT(DISTINCT CASE 
      WHEN LOWER(p.drug) LIKE '%warfarin%' 
        OR LOWER(p.drug) LIKE '%heparin%' 
        OR LOWER(p.drug) LIKE '%insulin%' 
        OR LOWER(p.drug) LIKE '%diazepam%' 
        OR LOWER(p.drug) LIKE '%lorazepam%' 
        OR LOWER(p.drug) LIKE '%morphine%' 
        OR LOWER(p.drug) LIKE '%fentanyl%' 
        OR LOWER(p.drug) LIKE '%digoxin%' 
        OR LOWER(p.drug) LIKE '%haloperidol%' 
      THEN p.drug 
    END) AS high_risk_drugs,
    COUNT(DISTINCT p.route) AS unique_routes,
    COUNT(DISTINCT p.drug) + 2 * COUNT(DISTINCT CASE 
      WHEN LOWER(p.drug) LIKE '%warfarin%' 
        OR LOWER(p.drug) LIKE '%heparin%' 
        OR LOWER(p.drug) LIKE '%insulin%' 
        OR LOWER(p.drug) LIKE '%diazepam%' 
        OR LOWER(p.drug) LIKE '%lorazepam%' 
        OR LOWER(p.drug) LIKE '%morphine%' 
        OR LOWER(p.drug) LIKE '%fentanyl%' 
        OR LOWER(p.drug) LIKE '%digoxin%' 
        OR LOWER(p.drug) LIKE '%haloperidol%' 
      THEN p.drug 
    END) + COUNT(DISTINCT p.route) AS score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
    AND p.starttime >= c.admittime
    AND p.starttime <= c.admittime + INTERVAL '7' DAY
  GROUP BY c.hadm_id
),

readmissions AS (
  SELECT 
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM cohort a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
),

tertiles AS (
  SELECT 
    m.hadm_id,
    m.score,
    NTILE(3) OVER (ORDER BY m.score) AS tertile
  FROM medication_scores m
)

SELECT 
  t.tertile,
  COUNT(*) AS count,
  MIN(t.score) AS min_score,
  MAX(t.score) AS max_score,
  AVG(DATE_DIFF(c.dischtime, c.admittime, DAY)) AS mean_los,
  AVG(CAST(c.hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_pct,
  AVG(CAST(r.readmitted_30d AS FLOAT64)) * 100 AS readmission_30d_pct
FROM tertiles t
JOIN cohort c ON t.hadm_id = c.hadm_id
LEFT JOIN readmissions r ON t.hadm_id = r.hadm_id
GROUP BY t.tertile
ORDER BY t.tertile;