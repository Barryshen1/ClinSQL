WITH patient_info AS (
  SELECT 
    pt.subject_id,
    pt.gender,
    DATE_SUB(CAST(CONCAT(CAST(pt.anchor_year AS STRING), '-01-01') AS DATE), INTERVAL pt.anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
)
SELECT MAX(duration_days) AS longest_duration
FROM (
  SELECT 
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN patient_info pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND TIMESTAMP_DIFF(p.starttime, TIMESTAMP(pt.birth_date), YEAR) BETWEEN 38 AND 48
    AND p.drug IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND REGEXP_CONTAINS(p.drug, r'lisinopril|enalapril|ramipril|perindopril|captopril|quinapril|benazepril|moexipril|trandolapril|fosinopril')
);