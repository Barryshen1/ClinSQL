WITH 
  -- Identify patients with asthma exacerbation
  asthma_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 85 AND 95
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code LIKE '493%'
      )
  ),

  -- Calculate composite comorbidity risk score
  comorbidity_scores AS (
    SELECT 
      subject_id,
      hadm_id,
      drg_code,
      drg_severity,
      drg_mortality
    FROM 
      `physionet-data.mimiciv_3_1_hosp.drgcodes`
  ),

  -- Merge patients with comorbidity scores
  patient_scores AS (
    SELECT 
      ap.subject_id,
      ap.hadm_id,
      ap.anchor_age,
      ap.gender,
      ap.hospital_expire_flag,
      cs.drg_severity AS comorbidity_score
    FROM 
      asthma_patients ap
    LEFT JOIN 
      comorbidity_scores cs
    ON 
      ap.hadm_id = cs.hadm_id
  ),

  -- Calculate quartiles of comorbidity scores
  score_quartiles AS (
    SELECT 
      subject_id,
      hadm_id,
      anchor_age,
      gender,
      hospital_expire_flag,
      comorbidity_score,
      NTILE(4) OVER (ORDER BY comorbidity_score) AS quartile
    FROM 
      patient_scores
  ),

  -- Identify cardiovascular and neurologic complications
  complications AS (
    SELECT 
      hadm_id,
      CASE
        WHEN icd_code LIKE '390%' OR icd_code LIKE '391%' OR icd_code LIKE '392%' THEN 'cardiovascular'
        WHEN icd_code LIKE '800%' OR icd_code LIKE '801%' OR icd_code LIKE '802%' THEN 'neurologic'
        ELSE NULL
      END AS complication_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  )

-- Final calculation of outcomes by quartile
SELECT 
  sq.quartile,
  AVG(CASE WHEN sq.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate,
  AVG(CASE WHEN c.complication_type = 'cardiovascular' THEN 1 ELSE 0 END) AS cardiovascular_complication_rate,
  AVG(CASE WHEN c.complication_type = 'neurologic' THEN 1 ELSE 0 END) AS neurologic_complication_rate
FROM 
  score_quartiles sq
LEFT JOIN 
  complications c
ON 
  sq.hadm_id = c.hadm_id
GROUP BY 
  sq.quartile;