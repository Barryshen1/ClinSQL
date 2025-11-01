WITH high_risk_drugs AS (
  SELECT 'warfarin' AS drug_name
  UNION ALL SELECT 'heparin'
  UNION ALL SELECT 'insulin'
  UNION ALL SELECT 'digoxin'
  UNION ALL SELECT 'amiodarone'
  -- Add more high-risk drug names as needed
),
eligible_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 78 AND 88
    AND d.icd_code = 'I21.4'
    AND d.icd_version = 10
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, age_at_admission
),
meds_7d AS (
  SELECT 
    e.subject_id,
    e.hadm_id,
    p.drug,
    p.route,
    CASE WHEN p.drug IN (SELECT drug_name FROM high_risk_drugs) THEN 1 ELSE 0 END AS is_high_risk
  FROM eligible_admissions e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON e.subject_id = p.subject_id AND e.hadm_id = p.hadm_id
    AND p.starttime >= e.admittime 
    AND p.starttime < e.admittime + INTERVAL 7 DAY
),
meds_summary AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS unique_drugs,
    COUNT(DISTINCT CASE WHEN is_high_risk = 1 THEN drug END) AS unique_high_risk_drugs,
    COUNT(DISTINCT route) AS unique_routes
  FROM meds_7d
  GROUP BY subject_id, hadm_id
),
score_calc AS (
  SELECT 
    e.subject_id,
    e.hadm_id,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    s.unique_drugs,
    s.unique_high_risk_drugs,
    s.unique_routes,
    s.unique_drugs + 2 * s.unique_high_risk_drugs + s.unique_routes AS score,
    TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) AS los
  FROM eligible_admissions e
  LEFT JOIN meds_summary s 
    ON e.subject_id = s.subject_id AND e.hadm_id = s.hadm_id
),
tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY score) AS tertile
  FROM score_calc
),
readmission AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) 
           BETWEEN dischtime AND dischtime + INTERVAL 30 DAY 
      THEN 1 
      ELSE 0 
    END AS readmitted
  FROM score_calc
)
SELECT 
  t.tertile,
  COUNT(*) AS count_patients,
  MIN(t.score) AS min_score,
  MAX(t.score) AS max_score,
  AVG(t.los) AS mean_los,
  SUM(t.hospital_expire_flag) / COUNT(*) * 100 AS mortality_percent,
  SUM(r.readmitted) / COUNT(*) * 100 AS readmission_percent
FROM tertiles t
LEFT JOIN readmission r 
  ON t.subject_id = r.subject_id AND t.hadm_id = r.hadm_id
GROUP BY t.tertile
ORDER BY t.tertile;