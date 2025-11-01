WITH 
  -- Identify population of interest
  population AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.anchor_age, 
      p.gender,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 43 AND 53
  ),

  -- Identify transplant diagnoses
  transplant_diagnoses AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code IN (
        'V42.0', 'V42.1', 'V42.2', 'V42.3', 'V42.4', 'V42.5', 'V42.6', 'V42.7', 'V42.8', 'V42.9',
        '996.81', '996.82', '996.83', '996.84', '996.85', '996.86', '996.87', '996.88', '996.89'
      )
  ),

  -- Filter population with transplant diagnoses
  transplant_population AS (
    SELECT 
      p.subject_id, 
      p.hadm_id,
      p.admittime,
      p.dischtime,
      p.hospital_expire_flag
    FROM 
      population p
    JOIN 
      transplant_diagnoses t 
        ON p.hadm_id = t.hadm_id
  ),

  -- Medications over first 7 days
  medications AS (
    SELECT 
      p.subject_id, 
      p.hadm_id,
      COUNT(DISTINCT prs.drug) AS medication_count
    FROM 
      transplant_population p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` prs 
        ON p.hadm_id = prs.hadm_id
    WHERE 
      prs.starttime <= TIMESTAMP_ADD(p.admittime, INTERVAL 7 DAY)
      AND prs.starttime >= p.admittime
    GROUP BY 
      p.subject_id, 
      p.hadm_id
  ),

  -- Combine with LOS, mortality, and readmission
  outcomes AS (
    SELECT 
      m.subject_id, 
      m.hadm_id,
      m.medication_count,
      TIMESTAMP_DIFF(tp.dischtime, tp.admittime, DAY) AS los,
      CASE 
        WHEN tp.hospital_expire_flag = 1 THEN 1 
        ELSE 0 
      END AS in_hospital_mortality,
      -- 30-day readmission flag
      CASE 
        WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
          WHERE a2.subject_id = tp.subject_id 
            AND a2.admittime BETWEEN TIMESTAMP_ADD(tp.admittime, INTERVAL 1 DAY) 
                                 AND TIMESTAMP_ADD(tp.admittime, INTERVAL 30 DAY)
        ) THEN 1 
        ELSE 0 
      END AS thirty_day_readmission
    FROM 
      medications m
    JOIN 
      transplant_population tp 
        ON m.hadm_id = tp.hadm_id
  ),

  -- Calculate quartiles
  quartiles AS (
    SELECT 
      APPROX_QUANTILES(medication_count, 4) AS quartiles
    FROM 
      outcomes
  )

-- Final calculation per quartile
SELECT 
  COUNT(CASE WHEN medication_count <= quartiles[OFFSET(0)] THEN 1 END) AS q1_n,
  AVG(CASE WHEN medication_count <= quartiles[OFFSET(0)] THEN medication_count END) AS q1_mean_score,
  AVG(CASE WHEN medication_count <= quartiles[OFFSET(0)] THEN los END) AS q1_los,
  AVG(CASE WHEN medication_count <= quartiles[OFFSET(0)] THEN in_hospital_mortality END) AS q1_mortality,
  AVG(CASE WHEN medication_count <= quartiles[OFFSET(0)] THEN thirty_day_readmission END) AS q1_readmission,

  COUNT(CASE WHEN medication_count BETWEEN quartiles[OFFSET(0)] + 1 AND quartiles[OFFSET(1)] THEN 1 END) AS q2_n,
  AVG(CASE WHEN medication_count BETWEEN quartiles[OFFSET(0)] + 1 AND quartiles[OFFSET(1)] THEN medication_count END) AS q2_mean_score,
  AVG(CASE WHEN medication_count BETWEEN quartiles[OFFSET(0)] + 1 AND quartiles[OFFSET(1)] THEN los END) AS q2_los,
  AVG(CASE WHEN medication_count BETWEEN quartiles[OFFSET(0)] + 1 AND quartiles[OFFSET(1)] THEN in_hospital_mortality END) AS q2_mortality,
  AVG(CASE WHEN medication_count BETWEEN quartiles[OFFSET(0)] + 1 AND quartiles[OFFSET(1)] THEN thirty_day_readmission END) AS q2_readmission,

  COUNT(CASE WHEN medication_count BETWEEN quartiles[OFFSET(1)] + 1 AND quartiles[OFFSET(2)] THEN 1 END) AS q3_n,
  AVG(CASE WHEN medication_count BETWEEN quartiles[OFFSET(1)] + 1 AND quartiles[OFFSET(2)] THEN medication_count END) AS q3_mean_score,
  AVG(CASE WHEN medication_count BETWEEN quartiles[OFFSET(1)] + 1 AND quartiles[OFFSET(2)] THEN los END) AS q3_los,
  AVG(CASE WHEN medication_count BETWEEN quartiles[OFFSET(1)] + 1 AND quartiles[OFFSET(2)] THEN in_hospital_mortality END) AS q3_mortality,
  AVG(CASE WHEN medication_count BETWEEN quartiles[OFFSET(1)] + 1 AND quartiles[OFFSET(2)] THEN thirty_day_readmission END) AS q3_readmission,

  COUNT(CASE WHEN medication_count > quartiles[OFFSET(2)] THEN 1 END) AS q4_n,
  AVG(CASE WHEN medication_count > quartiles[OFFSET(2)] THEN medication_count END) AS q4_mean_score,
  AVG(CASE WHEN medication_count > quartiles[OFFSET(2)] THEN los END) AS q4_los,
  AVG(CASE WHEN medication_count > quartiles[OFFSET(2)] THEN in_hospital_mortality END) AS q4_mortality,
  AVG(CASE WHEN medication_count > quartiles[OFFSET(2)] THEN thirty_day_readmission END) AS q4_readmission
FROM 
  outcomes o
CROSS JOIN 
  quartiles q;