WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1d
    ON d1.icd_code = d1d.icd_code AND d1.icd_version = d1d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2d
    ON d2.icd_code = d2d.icd_code AND d2.icd_version = d2d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND (
      (d1d.long_title LIKE '%diabetes mellitus type 2%' OR d1d.long_title LIKE '%type 2 diabetes%' OR d1.icd_code LIKE 'E11%')
      AND
      (d2d.long_title LIKE '%heart failure%' OR d2.icd_code LIKE 'I50%' OR d2.icd_code LIKE 'I42%')
    )
),
glp1_prescriptions AS (
  SELECT DISTINCT p.hadm_id,
    CASE 
      WHEN p.starttime BETWEEN a.admittime AND (a.admittime + INTERVAL 72 HOUR) THEN 1 
      ELSE 0 
    END AS started_in_72h,
    CASE 
      WHEN p.starttime BETWEEN (a.dischtime - INTERVAL 48 HOUR) AND a.dischtime THEN 1 
      ELSE 0 
    END AS on_in_last_48h
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN eligible_patients a ON p.hadm_id = a.hadm_id
  WHERE LOWER(p.drug) LIKE '%liraglutide%' 
     OR LOWER(p.drug) LIKE '%semaglutide%' 
     OR LOWER(p.drug) LIKE '%dulaglutide%' 
     OR LOWER(p.drug) LIKE '%exenatide%' 
     OR LOWER(p.drug) LIKE '%lixisenatide%' 
     OR LOWER(p.drug) LIKE '%albiglutide%' 
     OR LOWER(p.drug) LIKE '%tirzepatide%' 
     OR LOWER(p.drug) LIKE '%victoza%' 
     OR LOWER(p.drug) LIKE '%ozempic%' 
     OR LOWER(p.drug) LIKE '%trulicity%' 
     OR LOWER(p.drug) LIKE '%byetta%' 
     OR LOWER(p.drug) LIKE '%bydureon%' 
     OR LOWER(p.drug) LIKE '%adlyxin%' 
     OR LOWER(p.drug) LIKE '%tanzeum%' 
     OR LOWER(p.drug) LIKE '%mounjaro%'
)
SELECT 
  ROUND(100.0 * SUM(started_in_72h) / COUNT(*), 2) AS pct_started_in_72h,
  ROUND(100.0 * SUM(on_in_last_48h) / COUNT(*), 2) AS pct_on_in_last_48h,
  ROUND(100.0 * (SUM(on_in_last_48h) - SUM(started_in_72h)) / COUNT(*), 2) AS net_change_pct
FROM glp1_prescriptions;