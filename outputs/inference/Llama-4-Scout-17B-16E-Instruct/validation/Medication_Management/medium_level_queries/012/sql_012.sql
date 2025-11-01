WITH 
-- Patient selection
patients_selected AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 50 AND 60
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND a.subject_id IN (
      SELECT 
        subject_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code IN (
          SELECT 
            icd_code 
          FROM 
            `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
          WHERE 
            long_title IN ('Type 2 diabetes mellitus', 'Heart failure')
        )
    )
),

-- GLP-1 Initiation within first 12 hours
glp1_initiation AS (
  SELECT 
    ps.subject_id, 
    ps.hadm_id, 
    p.starttime AS glp1_starttime
  FROM 
    patients_selected ps
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
  ON ps.hadm_id = p.hadm_id
  WHERE 
    p.drug LIKE '%GLP-1%' 
    AND p.starttime BETWEEN ps.admittime AND TIMESTAMP_ADD(ps.admittime, INTERVAL 12 HOUR)
),

-- GLP-1 Prevalence in final 72 hours
glp1_prevalence_final AS (
  SELECT 
    ps.subject_id, 
    ps.hadm_id
  FROM 
    patients_selected ps
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
  ON ps.hadm_id = p.hadm_id
  WHERE 
    p.drug LIKE '%GLP-1%' 
    AND p.starttime <= TIMESTAMP_SUB(ps.dischtime, INTERVAL 72 HOUR)
    AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(ps.dischtime, INTERVAL 72 HOUR))
)

-- Calculate initiation and prevalence rates
SELECT 
  COUNT(DISTINCT CASE WHEN gi.glp1_starttime IS NOT NULL THEN ps.hadm_id END) / COUNT(DISTINCT ps.hadm_id) AS init_rate,
  COUNT(DISTINCT CASE WHEN gpf.hadm_id IS NOT NULL THEN ps.hadm_id END) / COUNT(DISTINCT ps.hadm_id) AS final_rate,
  COUNT(DISTINCT CASE WHEN gpf.hadm_id IS NOT NULL THEN ps.hadm_id END) / COUNT(DISTINCT ps.hadm_id) 
  - COUNT(DISTINCT CASE WHEN gi.glp1_starttime IS NOT NULL THEN ps.hadm_id END) / COUNT(DISTINCT ps.hadm_id) AS net_change
FROM 
  patients_selected ps
  LEFT JOIN glp1_initiation gi 
  ON ps.hadm_id = gi.hadm_id
  LEFT JOIN glp1_prevalence_final gpf 
  ON ps.hadm_id = gpf.hadm_id;