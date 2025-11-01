WITH 
-- Identify serotonergic medications
serotonergic_medications AS (
  SELECT 
    d.itemid,
    d.label AS drug
  FROM 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  WHERE 
    d.category = 'Medication'
    AND LOWER(d.label) LIKE '%serotonin%'  
),

-- Identify multi-trauma patients
multi_trauma_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    TIMESTAMPDIFF(DAY, ic.intime, ic.outtime) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE '800%' OR icd_code LIKE '810%' OR icd_code LIKE '820%' OR 
        icd_code LIKE '830%' OR icd_code LIKE '840%' OR icd_code LIKE '850%' OR 
        icd_code LIKE '860%' OR icd_code LIKE '870%' OR icd_code LIKE '880%' OR 
        icd_code LIKE '890%'
    )
    AND ic.intime BETWEEN a.admittime AND a.dischtime
),

-- Medication complexity and serotonergic risk
medication_complexity AS (
  SELECT 
    mtp.hadm_id,
    COUNT(DISTINCT ph.medication) AS medication_count,
    CASE 
      WHEN EXISTS (SELECT 1 FROM serotonergic_medications sm 
                    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON sm.itemid = dl.itemid 
                    WHERE LOWER(ph.medication) LIKE LOWER(CONCAT('%', sm.drug, '%'))) THEN 1 
      ELSE 0 
    END AS serotonergic_risk
  FROM 
    multi_trauma_patients mtp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON mtp.hadm_id = p.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph ON p.hadm_id = ph.hadm_id AND p.pharmacy_id = ph.pharmacy_id
  WHERE 
    p.starttime BETWEEN mtp.admittime AND mtp.admittime + INTERVAL 1 DAY
  GROUP BY 
    mtp.hadm_id
)

-- Final query
SELECT 
  APPROX_QUANTILES(medication_count, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(medication_count, 4)[OFFSET(2)] AS Median,
  APPROX_QUANTILES(medication_count, 4)[OFFSET(3)] AS Q3,
  AVG(medication_count) AS avg_medication_count,
  SUM(CASE WHEN serotonergic_risk = 1 THEN 1 ELSE 0 END) / COUNT(*) AS serotonergic_risk_percentage,
  AVG(mtp.los) AS los,
  SUM(CASE WHEN mtp.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality
FROM 
  medication_complexity mc
JOIN 
  multi_trauma_patients mtp ON mc.hadm_id = mtp.hadm_id;