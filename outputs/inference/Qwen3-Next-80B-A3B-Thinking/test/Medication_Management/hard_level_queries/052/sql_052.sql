WITH hhs_patients AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%hyperosmolar%' OR di.long_title LIKE '%HHS%'
),

cohort AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    CASE 
      WHEN p.gender = 'F' 
        AND p.anchor_age BETWEEN 68 AND 78 
        AND hhs_patients.subject_id IS NOT NULL 
      THEN 'HHS_Female_68_78'
      ELSE 'All_Inpatients'
    END AS cohort
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN hhs_patients
    ON a.subject_id = hhs_patients.subject_id AND a.hadm_id = hhs_patients.hadm_id
),

medication_complexity AS (
  SELECT 
    c.cohort,
    c.subject_id,
    COUNT(DISTINCT pr.drug) AS num_drugs
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
  WHERE pr.starttime >= a.admittime 
    AND pr.starttime <= a.admittime + INTERVAL '72' HOUR
  GROUP BY c.cohort, c.subject_id
),

hyperkalemia_risk_drugs AS (
  SELECT 'lisinopril' AS drug UNION ALL
  SELECT 'enalapril' UNION ALL
  SELECT 'losartan' UNION ALL
  SELECT 'valsartan' UNION ALL
  SELECT 'spironolactone' UNION ALL
  SELECT 'triamterene' UNION ALL
  SELECT 'trimethoprim' UNION ALL
  SELECT 'sulfamethoxazole' UNION ALL
  SELECT 'amlodipine' UNION ALL
  SELECT 'diltiazem' UNION ALL
  SELECT 'verapamil'
),

hyperkalemia_risk_patients AS (
  SELECT 
    c.cohort,
    c.subject_id,
    MAX(CASE WHEN hrd.drug IS NOT NULL THEN 1 ELSE 0 END) AS has_hyperkalemia_risk_drug
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  LEFT JOIN hyperkalemia_risk_drugs hrd
    ON pr.drug LIKE CONCAT('%', hrd.drug, '%')
  GROUP BY c.cohort, c.subject_id
),

los_mortality AS (
  SELECT 
    c.cohort,
    a.los AS length_of_stay,
    a.hospital_expire_flag
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
)

SELECT 
  cohort,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY num_drugs) AS median_num_drugs,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY num_drugs) AS q1_num_drugs,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY num_drugs) AS q3_num_drugs,
  AVG(has_hyperkalemia_risk_drug) * 100 AS percent_with_hyperkalemia_risk_drugs,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY length_of_stay) AS top_quartile_los,
  AVG(hospital_expire_flag) * 100 AS mortality_rate
FROM (
  SELECT 
    mc.cohort,
    mc.num_drugs,
    hkr.has_hyperkalemia_risk_drug,
    lm.length_of_stay,
    lm.hospital_expire_flag
  FROM medication_complexity mc
  JOIN hyperkalemia_risk_patients hkr
    ON mc.cohort = hkr.cohort AND mc.subject_id = hkr.subject_id
  JOIN los_mortality lm
    ON mc.cohort = lm.cohort AND mc.subject_id = lm.subject_id
) AS combined
GROUP BY cohort;