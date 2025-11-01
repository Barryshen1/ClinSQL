WITH 
-- Identify cohort and calculate medication complexity score
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    COUNT(DISTINCT prs.drug) AS medication_complexity_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` prs ON a.hadm_id = prs.hadm_id
  WHERE 
    a.admission_type = 'Inpatient'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND prs.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 7 DAY)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '% hepatic failure%'
    )
  GROUP BY 
    a.hadm_id, a.subject_id, p.anchor_age, p.gender
),
-- Stratify cohort into tertiles
cohort_tertiles AS (
  SELECT 
    hadm_id,
    subject_id,
    anchor_age,
    gender,
    medication_complexity_score,
    NTILE(3) OVER (ORDER BY medication_complexity_score) AS tertile
  FROM 
    cohort
),
-- Calculate outcomes
outcomes AS (
  SELECT 
    ct.hadm_id,
    ct.subject_id,
    ct.tertile,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    COALESCE(a.hospital_expire_flag, 0) AS in_hospital_mortality,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` readmission
        WHERE readmission.subject_id = ct.subject_id
        AND readmission.admittime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 30 DAY) AND TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS thirty_day_readmission
  FROM 
    cohort_tertiles ct
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON ct.hadm_id = a.hadm_id
)

-- Final aggregation
SELECT 
  tertile,
  AVG(los) AS avg_los,
  AVG(in_hospital_mortality) AS in_hospital_mortality_rate,
  AVG(thirty_day_readmission) AS thirty_day_readmission_rate
FROM 
  outcomes
GROUP BY 
  tertile;