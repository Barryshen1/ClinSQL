WITH 
-- Identify patients with ACS
acs_patients AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender
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
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND d.icd_code LIKE '%ACS%'  -- Assuming ACS is coded similarly
),

-- Compute lab instability score
lab_instability AS (
  SELECT 
    le.hadm_id,
    le.subject_id,
    COUNT(DISTINCT 
      CASE 
        WHEN d.category IN ('CRITICAL CARE', 'LABORATORY') 
        AND le.valuenum IS NOT NULL 
        AND (le.valueuom = 'mg/dL' OR le.valueuom = 'mmHg') 
        THEN le.itemid 
        ELSE NULL 
      END) AS lab_instability_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON 
    le.itemid = d.itemid
  WHERE 
    le.subject_id IN (SELECT subject_id FROM acs_patients)
  GROUP BY 
    le.hadm_id, le.subject_id
),

-- Calculate mortality and LOS for each quartile
quartiles AS (
  SELECT 
    hadm_id,
    subject_id,
    lab_instability_score,
    NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
  FROM 
    lab_instability
),

-- Calculate mortality and average LOS per quartile
mortality_los AS (
  SELECT 
    q.quartile,
    AVG(CASE 
        WHEN a.hospital_expire_flag = 1 THEN 1.0 
        ELSE 0 
      END) AS mortality_rate,
    AVG(DATE_DIFF(a.dischtime, a.admittime)) AS avg_los
  FROM 
    quartiles q
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    q.hadm_id = a.hadm_id
  GROUP BY 
    q.quartile
)

SELECT 
  quartile,
  mortality_rate,
  avg_los
FROM 
  mortality_los
ORDER BY 
  quartile;