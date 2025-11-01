WITH eligible_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON p.subject_id = d1.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1d
    ON d1.icd_code = d1d.icd_code AND d1.icd_version = d1d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON p.subject_id = d2.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2d
    ON d2.icd_code = d2d.icd_code AND d2.icd_version = d2d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND LOWER(d1d.long_title) LIKE '%diabetes%'
    AND LOWER(d2d.long_title) LIKE '%heart failure%'
),

insulin_drugs AS (
  SELECT 'insulin' AS drug_class, drug_pattern
  FROM UNNEST([
    '%insulin%', '%humulin%', '%lantus%', '%novolog%', '%levemir%', '%apidra%', '%fiasp%', '%toujeo%', '%basaglar%', '%nph%'
  ]) AS drug_pattern
),

oral_drugs AS (
  SELECT 'oral' AS drug_class, drug_pattern
  FROM UNNEST([
    '%metformin%', '%glipizide%', '%glyburide%', '%gliclazide%', '%glimepiride%', '%sitagliptin%', '%saxagliptin%', '%linagliptin%', '%empagliflozin%', '%dapagliflozin%', '%canagliflozin%', '%pioglitazone%', '%rosiglitazone%', '%repaglinide%', '%nateglinide%'
  ]) AS drug_pattern
),

prescriptions_filtered AS (
  SELECT
    p.subject_id,
    p.admittime,
    p.dischtime,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    CASE
      WHEN EXISTS (SELECT 1 FROM insulin_drugs id WHERE LOWER(pr.drug) LIKE id.drug_pattern) THEN 'insulin'
      WHEN EXISTS (SELECT 1 FROM oral_drugs od WHERE LOWER(pr.drug) LIKE od.drug_pattern) THEN 'oral'
      ELSE NULL
    END AS drug_class
  FROM eligible_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= p.admittime
    AND pr.starttime <= p.dischtime
    AND pr.drug IS NOT NULL
    AND (
      EXISTS (SELECT 1 FROM insulin_drugs id WHERE LOWER(pr.drug) LIKE id.drug_pattern)
      OR EXISTS (SELECT 1 FROM oral_drugs od WHERE LOWER(pr.drug) LIKE od.drug_pattern)
    )
),

time_windows AS (
  SELECT
    subject_id,
    drug_class,
    starttime,
    stoptime,
    admittime,
    dischtime,
    DATE_ADD(admittime, INTERVAL 48 HOUR) AS first_48h_end,
    DATE_SUB(dischtime, INTERVAL 24 HOUR) AS final_24h_start
  FROM prescriptions_filtered
),

patient_summary AS (
  SELECT
    drug_class,
    COUNT(DISTINCT CASE WHEN starttime BETWEEN admittime AND first_48h_end THEN subject_id END) AS initiated_in_first_48h,
    COUNT(DISTINCT CASE WHEN (stoptime IS NULL OR stoptime >= final_24h_start) AND starttime <= final_24h_start THEN subject_id END) AS continued_into_final_24h,
    COUNT(DISTINCT CASE WHEN stoptime < final_24h_start AND starttime < final_24h_start THEN subject_id END) AS discontinued,
    COUNT(DISTINCT CASE WHEN starttime BETWEEN admittime AND first_48h_end THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id) AS pct_first_48h,
    COUNT(DISTINCT CASE WHEN (stoptime IS NULL OR stoptime >= final_24h_start) AND starttime <= final_24h_start THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id) AS pct_final_24h
  FROM time_windows
  GROUP BY drug_class
)

SELECT
  drug_class,
  ROUND(pct_first_48h, 2) AS percent_on_drug_first_48h,
  ROUND(pct_final_24h, 2) AS percent_on_drug_final_24h,
  initiated_in_first_48h AS initiated_count,
  continued_into_final_24h AS continued_count,
  discontinued AS discontinued_count
FROM patient_summary
ORDER BY drug_class;