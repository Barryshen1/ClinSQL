WITH 
-- Identify AKI patients
aki_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.labevents
  WHERE itemid = 220050 AND valuenum > 1.5  -- Creatinine > 1.5 mg/dL as a simple AKI criterion
),

-- Calculate medication complexity score (simple count of unique medications)
medication_complexity AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    COUNT(DISTINCT p.drug) AS medication_count
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.prescriptions p ON a.hadm_id = p.hadm_id AND p.starttime <= a.dischtime AND (p.stoptime IS NULL OR p.stoptime >= a.admittime)
  GROUP BY a.subject_id, a.hadm_id
),

-- Stratify into quintiles based on medication complexity score
quintiles AS (
  SELECT 
    subject_id, 
    hadm_id, 
    medication_count,
    NTILE(5) OVER (ORDER BY medication_count) AS quintile
  FROM medication_complexity
),

-- Calculate outcomes
outcomes AS (
  SELECT 
    q.quintile,
    AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(a.hadm_id) AS inpatient_mortality_rate,
    SUM(CASE WHEN EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.admissions readmission
      WHERE readmission.subject_id = a.subject_id
      AND readmission.admittime BETWEEN a.dischtime AND TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END) / COUNT(a.hadm_id) AS readmission_rate,
    COUNT(DISTINCT CASE 
      WHEN p.drug LIKE '%anticoagulant%' AND EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.prescriptions p2
        WHERE p2.hadm_id = p.hadm_id
        AND p2.drug LIKE '%opioid%'
      ) THEN p.hadm_id 
    END) AS anticoagulant_opioid_coadministration
  FROM quintiles q
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON q.hadm_id = a.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.patients pt ON a.subject_id = pt.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.prescriptions p ON a.hadm_id = p.hadm_id
  WHERE pt.anchor_age BETWEEN 84 AND 94 AND pt.gender = 'F' AND a.hadm_id IN (SELECT hadm_id FROM aki_patients)
  GROUP BY q.quintile
)

SELECT * FROM outcomes;