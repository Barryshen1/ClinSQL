WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),
diagnoses AS (
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
  GROUP BY d.hadm_id
  HAVING has_diabetes = 1 AND has_heart_failure = 1
),
cohort_with_diagnoses AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime
  FROM cohort c
  INNER JOIN diagnoses d 
    ON c.hadm_id = d.hadm_id
),
prescriptions_with_status AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug,
    p.route,
    p.poe_id,
    p.poe_seq
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.poe` poe 
    ON p.poe_id = poe.poe_id AND p.poe_seq = poe.poe_seq
  WHERE 
    poe.order_status NOT IN ('discontinued', 'stopped', 'cancelled')
),
medication_flags AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN pr.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 48 HOUR 
             AND LOWER(pr.drug) LIKE '%insulin%' 
             THEN 1 ELSE 0 END) AS insulin_first_48h,
    MAX(CASE WHEN pr.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 48 HOUR 
             AND (LOWER(pr.route) LIKE '%po%' OR LOWER(pr.route) LIKE '%oral%')
             AND (LOWER(pr.drug) LIKE '%metformin%' OR 
                  LOWER(pr.drug) LIKE '%glipizide%' OR 
                  LOWER(pr.drug) LIKE '%glyburide%' OR 
                  LOWER(pr.drug) LIKE '%glimepiride%' OR 
                  LOWER(pr.drug) LIKE '%pioglitazone%' OR 
                  LOWER(pr.drug) LIKE '%rosiglitazone%' OR 
                  LOWER(pr.drug) LIKE '%sitagliptin%' OR 
                  LOWER(pr.drug) LIKE '%saxagliptin%' OR 
                  LOWER(pr.drug) LIKE '%linagliptin%' OR 
                  LOWER(pr.drug) LIKE '%alogliptin%' OR 
                  LOWER(pr.drug) LIKE '%canagliflozin%' OR 
                  LOWER(pr.drug) LIKE '%dapagliflozin%' OR 
                  LOWER(pr.drug) LIKE '%empagliflozin%')
             THEN 1 ELSE 0 END) AS oral_first_48h,
    MAX(CASE WHEN pr.starttime BETWEEN c.dischtime - INTERVAL 24 HOUR AND c.dischtime 
             AND LOWER(pr.drug) LIKE '%insulin%' 
             THEN 1 ELSE 0 END) AS insulin_final_24h,
    MAX(CASE WHEN pr.starttime BETWEEN c.dischtime - INTERVAL 24 HOUR AND c.dischtime 
             AND (LOWER(pr.route) LIKE '%po%' OR LOWER(pr.route) LIKE '%oral%')
             AND (LOWER(pr.drug) LIKE '%metformin%' OR 
                  LOWER(pr.drug) LIKE '%glipizide%' OR 
                  LOWER(pr.drug) LIKE '%glyburide%' OR 
                  LOWER(pr.drug) LIKE '%glimepiride%' OR 
                  LOWER(pr.drug) LIKE '%pioglitazone%' OR 
                  LOWER(pr.drug) LIKE '%rosiglitazone%' OR 
                  LOWER(pr.drug) LIKE '%sitagliptin%' OR 
                  LOWER(pr.drug) LIKE '%saxagliptin%' OR 
                  LOWER(pr.drug) LIKE '%linagliptin%' OR 
                  LOWER(pr.drug) LIKE '%alogliptin%' OR 
                  LOWER(pr.drug) LIKE '%canagliflozin%' OR 
                  LOWER(pr.drug) LIKE '%dapagliflozin%' OR 
                  LOWER(pr.drug) LIKE '%empagliflozin%')
             THEN 1 ELSE 0 END) AS oral_final_24h
  FROM cohort_with_diagnoses c
  LEFT JOIN prescriptions_with_status pr 
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)
SELECT 
  (SUM(insulin_first_48h) * 100.0 / COUNT(*)) AS insulin_first_48h_percent,
  (SUM(oral_first_48h) * 100.0 / COUNT(*)) AS oral_first_48h_percent,
  (SUM(insulin_final_24h) * 100.0 / COUNT(*)) AS insulin_final_24h_percent,
  (SUM(oral_final_24h) * 100.0 / COUNT(*)) AS oral_final_24h_percent
FROM medication_flags;