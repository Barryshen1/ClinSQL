WITH 
  -- Define the population of interest: male Medicare patients aged 50-60 admitted from ED with lower GI bleed
  inclusion_criteria AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      a.admit_provider_id,
      a.admission_location,
      a.admission_type,
      p.anchor_age,
      p.gender,
      a.insurance,
      a.edregtime,
      a.edouttime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      a.admission_type = 'Emergency'
      AND a.admission_location = 'ED'
      AND p.gender = 'M'
      AND p.anchor_age BETWEEN 50 AND 60
      AND a.insurance = 'Medicare'
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE 
          d.hadm_id = a.hadm_id
          AND d.icd_code LIKE 'K62.1'  -- Lower GI bleeding
          AND d.seq_num = 1  -- Principal diagnosis
      )
  ),
  
  -- Calculate length of stay (LOS) for each admission
  los AS (
    SELECT 
      ic.hadm_id,
      TIMESTAMPDIFF(DAY, a.admittime, a.dischtime) + 
      (CASE 
         WHEN a.dischtime IS NULL THEN 1 
         ELSE 0 
       END) AS los_days
    FROM 
      inclusion_criteria ic
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      ic.hadm_id = a.hadm_id
  ),
  
  -- Identify readmitted patients within 30 days
  readmitted_patients AS (
    SELECT 
      a.hadm_id,
      MIN(b.admittime) AS readmit_time
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      inclusion_criteria ic
    ON 
      a.subject_id = ic.subject_id
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` b
    ON 
      ic.subject_id = b.subject_id
    WHERE 
      a.dischtime IS NOT NULL
      AND b.admittime BETWEEN a.dischtime AND TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
      AND b.admission_type <> 'Re-admit'
    GROUP BY 
      a.hadm_id
  ),
  
  -- Merge LOS and readmission status
  final_results AS (
    SELECT 
      COALESCE(rp.hadm_id, ic.hadm_id) AS hadm_id,
      los.los_days,
      CASE 
        WHEN rp.hadm_id IS NOT NULL THEN 1 
        ELSE 0 
      END AS readmitted
    FROM 
      los
    LEFT JOIN 
      readmitted_patients rp
    ON 
      los.hadm_id = rp.hadm_id
    INNER JOIN 
      inclusion_criteria ic
    ON 
      los.hadm_id = ic.hadm_id
  )

SELECT 
  SUM(readmitted) / COUNT(*) AS readmission_rate,
  PERCENTILE_CONT(0.5)(los_days) WITHIN GROUP (ORDER BY los_days) FILTER (WHERE readmitted = 1) AS median_los_readmitted,
  PERCENTILE_CONT(0.5)(los_days) WITHIN GROUP (ORDER BY los_days) FILTER (WHERE readmitted = 0) AS median_los_not_readmitted,
  AVG(CASE WHEN los_days > 6 AND readmitted = 1 THEN 1 ELSE 0 END) AS percent_los_gt_6_readmitted,
  AVG(CASE WHEN los_days > 6 AND readmitted = 0 THEN 1 ELSE 0 END) AS percent_los_gt_6_not_readmitted
FROM 
  final_results;