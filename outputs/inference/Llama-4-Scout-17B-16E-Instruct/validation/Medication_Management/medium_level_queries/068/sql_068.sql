WITH 
-- Identify patients with T2DM and HF
t2dm_hf_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN (
          '250.00', '250.01', '250.02', '250.03', '250.10', '250.11', '250.12', '250.13', 
          '250.20', '250.21', '250.22', '250.23', '250.30', '250.31', '250.32', '250.33', 
          '250.40', '250.41', '250.42', '250.43', '250.50', '250.51', '250.52', '250.53', 
          '250.60', '250.61', '250.62', '250.63', '250.70', '250.71', '250.72', '250.73', 
          '250.80', '250.81', '250.82', '250.83', '250.90', '250.91', '250.92', '250.93'
        )  -- T2DM ICD codes
    )
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code = '428.0'  -- HF ICD code
    )
),

-- Identify insulin prescriptions
insulin_prescriptions AS (
  SELECT 
    subject_id, 
    hadm_id,
    pharmacy_id,
    order_provider_id,
    starttime,
    stoptime,
    drug,
    dose_val_rx,
    dose_unit_rx,
    route
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    drug LIKE '%insulin%'
),

-- Categorize insulin therapy
insulin_therapy AS (
  SELECT 
    t2dm_hf.subject_id, 
    t2dm_hf.hadm_id,
    ip.drug,
    ip.starttime,
    ip.stoptime,
    ip.dose_val_rx,
    ip.dose_unit_rx,
    ip.route,
    CASE 
      WHEN ip.drug LIKE '%basal%' THEN 'basal'
      WHEN ip.drug LIKE '%bolus%' THEN 'bolus'
      WHEN ip.drug LIKE '%sliding%' THEN 'sliding-scale'
      ELSE 'other'
    END AS insulin_type
  FROM 
    t2dm_hf_patients t2dm_hf
  JOIN 
    insulin_prescriptions ip 
      ON t2dm_hf.hadm_id = ip.hadm_id
),

-- Calculate initiation of insulin therapy in the first 48 hours
initiation AS (
  SELECT 
    hadm_id,
    insulin_type,
    COUNT(DISTINCT drug) AS num_drugs,
    AVG(CAST(dose_val_rx AS FLOAT64)) AS avg_dose
  FROM 
    insulin_therapy
  WHERE 
    insulin_type IN ('basal', 'bolus', 'sliding-scale')
    AND starttime BETWEEN TIMESTAMP_SUB(admittime, INTERVAL 48 HOUR) AND admittime
  GROUP BY 
    hadm_id, insulin_type
),

-- Calculate final insulin therapy in the last 12 hours
final_therapy AS (
  SELECT 
    hadm_id,
    insulin_type,
    COUNT(DISTINCT drug) AS num_drugs,
    AVG(CAST(dose_val_rx AS FLOAT64)) AS avg_dose
  FROM 
    insulin_therapy
  WHERE 
    insulin_type IN ('basal', 'bolus', 'sliding-scale')
    AND starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime
  GROUP BY 
    hadm_id, insulin_type
)

-- Combine initiation and final therapy
SELECT 
  i.hadm_id,
  i.insulin_type AS init_insulin_type,
  i.num_drugs AS init_num_drugs,
  i.avg_dose AS init_avg_dose,
  f.insulin_type AS final_insulin_type,
  f.num_drugs AS final_num_drugs,
  f.avg_dose AS final_avg_dose
FROM 
  initiation i
FULL OUTER JOIN 
  final_therapy f 
    ON i.hadm_id = f.hadm_id AND i.insulin_type = f.insulin_type;