WITH 
  eligible_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.gender,
      p.anchor_age,
      di.long_title AS diagnosis,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      a.hadm_id = d.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON 
      d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 44 AND 54
      AND di.long_title LIKE '%Intracranial hemorrhage%'
  ),
  patient_risk AS (
    SELECT 
      subject_id,
      hadm_id,
      -- Placeholder for composite risk score calculation
      -- For demonstration, assume a simple risk score
      CASE 
        WHEN hospital_expire_flag = 1 THEN 1
        ELSE 0
      END AS risk_score
    FROM 
      eligible_patients
  ),
  quartile_data AS (
    SELECT 
      subject_id,
      hadm_id,
      risk_score,
      NTILE(4) OVER (ORDER BY risk_score) AS risk_score_quartile
    FROM 
      patient_risk
  ),
  outcomes AS (
    SELECT 
      q.risk_score_quartile,
      COUNT(DISTINCT q.hadm_id) AS patient_count,
      SUM(CASE WHEN ep.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) AS in_hospital_mortality,
      -- Cardiac and neurologic complication rates calculation
      -- For demonstration, assume these are available
      SUM(CASE WHEN c.complication = 'cardiac' THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) AS cardiac_complication_rate,
      SUM(CASE WHEN c.complication = 'neurologic' THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) AS neurologic_complication_rate,
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TIMESTAMPDIFF(DAY, ep.admittime, ep.dischtime)) AS median_los
    FROM 
      quartile_data q
    JOIN 
      eligible_patients ep
    ON 
      q.hadm_id = ep.hadm_id
    -- Join complications if available
    -- LEFT JOIN complications c ON q.hadm_id = c.hadm_id
    GROUP BY 
      q.risk_score_quartile
  )
SELECT 
  *
FROM 
  outcomes;