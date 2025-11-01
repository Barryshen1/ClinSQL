WITH 
  -- Identify lower GI bleed admissions
  lgib_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.dischtime,
      EXTRACT(DAY FROM a.dischtime - a.admittime) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 71 AND 81
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE 
          d.hadm_id = a.hadm_id
          AND d.icd_code LIKE 'K62.1%'  -- Lower GI bleed ICD code
      )
  ),
  
  -- Categorize admissions by length of stay
  los_categories AS (
    SELECT 
      hadm_id,
      subject_id,
      anchor_age,
      gender,
      admittime,
      dischtime,
      los,
      CASE 
        WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
        ELSE 'Other'
      END AS los_category
    FROM 
      lgib_admissions
  ),
  
  -- Identify primary and secondary diagnoses
  diagnoses AS (
    SELECT 
      hadm_id,
      subject_id,
      icd_code,
      seq_num,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY seq_num) AS diag_rank
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  ),
  
  -- Count radiography/CTs per admission
  radiography_cts AS (
    SELECT 
      hadm_id,
      COUNT(*) AS radiography_ct_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE 
      hcpcs_cd LIKE '74%'  -- Radiography HCPCS code range
      OR hcpcs_cd LIKE '87%'  -- CT scan HCPCS code range
    GROUP BY 
      hadm_id
  )

SELECT 
  lc.los_category,
  CASE 
    WHEN d.diag_rank = 1 THEN 'Primary'
    ELSE 'Secondary'
  END AS diagnosis_type,
  AVG(rct.radiography_ct_count) AS mean_radiography_cts
FROM 
  los_categories lc
JOIN 
  diagnoses d 
    ON lc.hadm_id = d.hadm_id
JOIN 
  radiography_cts rct 
    ON lc.hadm_id = rct.hadm_id
GROUP BY 
  lc.los_category,
  diagnosis_type
ORDER BY 
  lc.los_category,
  diagnosis_type;