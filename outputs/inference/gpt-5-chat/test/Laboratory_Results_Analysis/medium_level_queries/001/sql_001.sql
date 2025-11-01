WITH ami_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, d_icd.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.subject_id = d_icd.subject_id
    AND a.hadm_id = d_icd.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '410%') -- ICD-9 AMI
      OR (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'I21%') -- ICD-10 AMI
    )
), troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
), first_troponin AS (
  SELECT l.subject_id, l.hadm_id, l.charttime, l.valuenum,
         ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_itemids t
    ON l.itemid = t.itemid
  JOIN ami_patients ap
    ON l.subject_id = ap.subject_id
    AND l.hadm_id = ap.hadm_id
  WHERE l.valuenum IS NOT NULL
)
SELECT
  CASE
    WHEN valuenum < 0.01 THEN 'Normal'
    WHEN valuenum >= 0.01 AND valuenum < 0.1 THEN 'Borderline'
    WHEN valuenum >= 0.1 THEN 'Elevated'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS num_patients
FROM first_troponin
WHERE rn = 1
GROUP BY troponin_category
ORDER BY troponin_category;