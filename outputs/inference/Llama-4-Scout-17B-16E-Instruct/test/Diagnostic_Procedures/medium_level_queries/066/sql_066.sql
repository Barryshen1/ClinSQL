WITH 
  patients_with_asthma AS (
    SELECT 
      a.subject_id, 
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 88 AND 98
      AND d.icd_code LIKE '%493%'  
  ),
  
  admissions_with_procedures AS (
    SELECT 
      hadm_id,
      COUNT(icd_code) AS num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    WHERE 
      hadm_id IN (SELECT hadm_id FROM patients_with_asthma)
    GROUP BY 
      hadm_id
  ),
  
  los_categories AS (
    SELECT 
      hadm_id,
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions`
  )

SELECT 
  los_group,
  APPROX_QUANTILES(num_procedures, 0.25) AS p25,
  APPROX_QUANTILES(num_procedures, 0.5) AS p50,
  APPROX_QUANTILES(num_procedures, 0.75) AS p75
FROM (
  SELECT 
    CASE 
      WHEN lc.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN lc.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    awp.num_procedures
  FROM 
    los_categories lc
  JOIN 
    admissions_with_procedures awp ON lc.hadm_id = awp.hadm_id
  WHERE 
    lc.los_days BETWEEN 1 AND 7
) AS percentiles_data
GROUP BY 
  los_group;