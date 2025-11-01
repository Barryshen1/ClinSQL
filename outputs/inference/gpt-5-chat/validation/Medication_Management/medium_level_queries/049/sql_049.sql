WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, p.gender, p.anchor_age,
         a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE (dd.icd_code LIKE '250%' OR dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%' OR dd.icd_code LIKE 'E12%' OR dd.icd_code LIKE 'E13%' OR dd.icd_code LIKE 'E14%')
      GROUP BY hadm_id
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE (dd.icd_code LIKE '428%' OR dd.icd_code LIKE 'I50%')
      GROUP BY hadm_id
    )
),
rx_classified AS (
  SELECT c.hadm_id,
         CASE
           WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Biguanide'
           WHEN LOWER(pr.drug) LIKE '%glipizide%' 
             OR LOWER(pr.drug) LIKE '%glyburide%' 
             OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
           WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
           WHEN LOWER(pr.drug) LIKE '%sitagliptin%' 
             OR LOWER(pr.drug) LIKE '%linagliptin%' 
             OR LOWER(pr.drug) LIKE '%alogliptin%' 
             OR LOWER(pr.drug) LIKE '%saxagliptin%' THEN 'DPP-4 inhibitor'
           WHEN LOWER(pr.drug) LIKE '%liraglutide%' 
             OR LOWER(pr.drug) LIKE '%exenatide%' 
             OR LOWER(pr.drug) LIKE '%semaglutide%' 
             OR LOWER(pr.drug) LIKE '%dulaglutide%' THEN 'GLP-1 agonist'
           WHEN LOWER(pr.drug) LIKE '%empagliflozin%' 
             OR LOWER(pr.drug) LIKE '%dapagliflozin%' 
             OR LOWER(pr.drug) LIKE '%canagliflozin%' THEN 'SGLT2 inhibitor'
           WHEN LOWER(pr.drug) LIKE '%pioglitazone%' 
             OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinedione'
           ELSE NULL
         END AS drug_class,
         CASE
           WHEN pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) THEN 'first72h'
           WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime THEN 'final24h'
           ELSE NULL
         END AS time_window
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
   AND c.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
),
window_counts AS (
  SELECT time_window, drug_class,
         COUNT(DISTINCT hadm_id) AS hadm_count
  FROM rx_classified
  WHERE drug_class IS NOT NULL AND time_window IS NOT NULL
  GROUP BY time_window, drug_class
),
total_counts AS (
  SELECT time_window, COUNT(DISTINCT hadm_id) AS total_hadm
  FROM rx_classified
  WHERE time_window IS NOT NULL
  GROUP BY time_window
)
SELECT w.time_window, w.drug_class,
       ROUND(100.0 * w.hadm_count / t.total_hadm, 2) AS pct_admissions
FROM window_counts w
JOIN total_counts t
  ON w.time_window = t.time_window
ORDER BY w.time_window, w.drug_class;