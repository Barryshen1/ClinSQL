WITH cohort AS (
  SELECT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (a.dischtime - a.admittime) >= INTERVAL 72 HOUR
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_desc 
        ON d.icd_code = d_desc.icd_code AND d.icd_version = d_desc.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND d_desc.long_title LIKE '%type 2 diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_desc 
        ON d.icd_code = d_desc.icd_code AND d.icd_version = d_desc.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND d_desc.long_title LIKE '%heart failure%'
    )
),
glp1_prescriptions AS (
  SELECT p.hadm_id, p.starttime, p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%victoza%'
     OR LOWER(p.drug) LIKE '%saxenda%'
     OR LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%ozempic%'
     OR LOWER(p.drug) LIKE '%rybelsus%'
     OR LOWER(p.drug) LIKE '%exenatide%'
     OR LOWER(p.drug) LIKE '%byetta%'
     OR LOWER(p.drug) LIKE '%bydureon%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%trulicity%'
     OR LOWER(p.drug) LIKE '%albiglutide%'
     OR LOWER(p.drug) LIKE '%tanzeum%'
     OR LOWER(p.drug) LIKE '%lixisenatide%'
     OR LOWER(p.drug) LIKE '%adlyxin%'
     OR LOWER(p.drug) LIKE '%tirzepatide%'
     OR LOWER(p.drug) LIKE '%mounjaro%'
),
patient_status AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN gp.starttime <= c.admittime + INTERVAL 12 HOUR THEN 1 ELSE 0 END) AS init_12h,
    MAX(CASE WHEN gp.starttime <= c.admittime + INTERVAL 72 HOUR
             AND (gp.stoptime > c.admittime + INTERVAL 72 HOUR OR gp.stoptime IS NULL)
             THEN 1 ELSE 0 END) AS prev_72h
  FROM cohort c
  LEFT JOIN glp1_prescriptions gp 
    ON c.hadm_id = gp.hadm_id
  GROUP BY c.hadm_id
)
SELECT
  AVG(init_12h) * 100 AS first_12hr_initiation_pct,
  AVG(prev_72h) * 100 AS final_72hr_prevalence_pct,
  (AVG(prev_72h) - AVG(init_12h)) * 100 AS net_change_pct
FROM patient_status;