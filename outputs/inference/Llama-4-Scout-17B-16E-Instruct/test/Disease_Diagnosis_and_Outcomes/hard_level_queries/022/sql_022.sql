WITH 
  -- Identify AKI and ARDS
  aki_ards AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      COUNT(DISTINCT CASE WHEN di.icd_code LIKE '584%' THEN di.icd_code END) AS aki_count,
      COUNT(DISTINCT CASE WHEN di.icd_code LIKE '518.8%' THEN di.icd_code END) AS ards_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    GROUP BY 
      a.subject_id, a.hadm_id
  ),
  
  -- Patient demographics and comorbidities
  patient_info AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      COUNT(DISTINCT di.icd_code) AS comorbidity_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    GROUP BY 
      p.subject_id, p.gender, p.anchor_age
  ),
  
  -- Composite risk score
  risk_score AS (
    SELECT 
      pi.subject_id,
      pi.anchor_age,
      pi.gender,
      pi.comorbidity_count * 5 + 
      CASE 
        WHEN ards.ards_count > 0 THEN 50 
        ELSE 0 
      END AS risk_score
    FROM 
      patient_info pi
    JOIN 
      aki_ards ards ON pi.subject_id = ards.subject_id
    WHERE 
      pi.gender = 'F' AND pi.anchor_age BETWEEN 40 AND 50
  ),

  -- Quintile calculation
  quintiles AS (
    SELECT 
      subject_id,
      anchor_age,
      gender,
      risk_score,
      NTILE(5) OVER (ORDER BY risk_score) AS quintile
    FROM 
      risk_score
  ),

  -- Post-discharge mortality and LOS
  outcomes AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      TIMESTAMPDIFF(DAY, a.dischtime, p.dod) AS post_discharge_los,
      CASE 
        WHEN p.dod IS NOT NULL AND TIMESTAMPDIFF(DAY, a.dischtime, p.dod) <= 30 THEN 1 
        ELSE 0 
      END AS thirty_day_mortality
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  )

-- Final aggregation
SELECT 
  q.quintile,
  COUNT(DISTINCT q.subject_id) AS N,
  AVG(o.thirty_day_mortality) * 100 AS thirty_day_mortality_pct,
  AVG(CASE WHEN ards.ards_count > 0 THEN 1 ELSE 0 END) * 100 AS ards_cooccurrence_pct,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.post_discharge_los) AS median_survivor_los
FROM 
  quintiles q
JOIN 
  outcomes o ON q.subject_id = o.subject_id
JOIN 
  aki_ards ards ON q.subject_id = ards.subject_id
GROUP BY 
  q.quintile
ORDER BY 
  q.quintile;