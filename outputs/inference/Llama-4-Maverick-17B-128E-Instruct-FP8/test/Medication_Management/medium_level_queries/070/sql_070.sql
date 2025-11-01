WITH t2dm_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE (h.icd_version = 9 AND h.icd_code LIKE '250%' AND (SUBSTR(h.icd_code, 5, 1) = '0' OR SUBSTR(h.icd_code, 5, 1) = '2'))
     OR (h.icd_version = 10 AND d.icd_code LIKE 'E11%')
),
hf_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE (h.icd_version = 9 AND h.icd_code LIKE '428%')
     OR (h.icd_version = 10 AND h.icd_code LIKE 'I50%')
),
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 68 AND 78
    AND a.hadm_id IN (SELECT hadm_id FROM t2dm_patients INTERSECT DISTINCT SELECT hadm_id FROM hf_patients)
),
medications AS (
  SELECT DISTINCT pr.hadm_id, 
         CASE 
           WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
           WHEN LOWER(pr.drug) LIKE '%sulfonylurea%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' THEN 'Sulfonylureas'
           WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
           WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitors'
         END AS medication_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN eligible_patients ep ON pr.hadm_id = ep.hadm_id
  WHERE pr.starttime <= ep.dischtime AND pr.stoptime >= ep.admittime
    AND (LOWER(pr.drug) LIKE '%metformin%' 
         OR LOWER(pr.drug) LIKE '%sulfonylurea%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%'
         OR LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%'
         OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%')
),
medication_prevalence AS (
  SELECT m.hadm_id, m.medication_class,
         CASE WHEN pr.starttime <= ep.admittime + INTERVAL 2 DAY THEN 1 ELSE 0 END AS first_48h,
         CASE WHEN pr.stoptime >= ep.dischtime - INTERVAL 12 HOUR THEN 1 ELSE 0 END AS last_12h
  FROM medications m
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON m.hadm_id = pr.hadm_id
  JOIN eligible_patients ep ON m.hadm_id = ep.hadm_id
)
SELECT medication_class,
       SUM(first_48h) / COUNT(DISTINCT hadm_id) * 100 AS prevalence_first_48h,
       SUM(last_12h) / COUNT(DISTINCT hadm_id) * 100 AS prevalence_last_12h,
       (SUM(last_12h) / COUNT(DISTINCT hadm_id) * 100) - (SUM(first_48h) / COUNT(DISTINCT hadm_id) * 100) AS net_change
FROM medication_prevalence
GROUP BY medication_class;