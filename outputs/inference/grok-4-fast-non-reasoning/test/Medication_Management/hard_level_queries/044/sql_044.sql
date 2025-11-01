WITH pe_cohort AS (
  -- Base cohort: women 64-74 with PE (ICD-10 I26*)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
        ON d.icd_code = icd.icd_code 
        AND d.icd_version = icd.icd_version
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id 
        AND CAST(d.icd_version AS STRING) = '10'
        AND d.icd_code LIKE 'I26%'
        AND icd.long_title LIKE '%embolism%'  -- Ensure specificity to PE
    )
),

med_scores AS (
  -- Distinct meds in first 24h from prescriptions and pharmacy
  SELECT 
    hadm_id,
    COUNT(DISTINCT drug_name) AS med_score
  FROM (
    -- Prescriptions
    SELECT 
      pr.hadm_id,
      LOWER(TRIM(pr.drug)) AS drug_name
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN pe_cohort c ON pr.subject_id = c.subject_id AND pr.hadm_id = c.hadm_id
    WHERE pr.drug IS NOT NULL 
      AND pr.drug != ''
      AND pr.starttime >= c.admittime 
      AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
    
    UNION ALL
    
    -- Pharmacy (dispensed)
    SELECT 
      ph.hadm_id,
      LOWER(TRIM(ph.medication)) AS drug_name
    FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    INNER JOIN pe_cohort c ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
    WHERE ph.medication IS NOT NULL 
      AND ph.medication != ''
      AND ph.starttime >= c.admittime 
      AND ph.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
  )
  GROUP BY hadm_id
),

outcomes AS (
  -- LOS and 30-day readmission
  SELECT 
    c.*,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` readmit
        WHERE readmit.subject_id = c.subject_id
          AND readmit.hadm_id != c.hadm_id
          AND readmit.admittime > c.dischtime
          AND readmit.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmit_30d
  FROM pe_cohort c
),

final_data AS (
  SELECT 
    o.*,
    COALESCE(ms.med_score, 0) AS med_score,
    NTILE(3) OVER (ORDER BY COALESCE(ms.med_score, 0)) AS tertile_num
  FROM outcomes o
  LEFT JOIN med_scores ms ON o.hadm_id = ms.hadm_id
)

-- Aggregate by tertile
SELECT 
  tertile_num,
  COUNT(*) AS admissions,
  CONCAT(CAST(MIN(med_score) AS STRING), '-', CAST(MAX(med_score) AS STRING)) AS med_score_range,
  ROUND(AVG(los), 2) AS avg_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_pct,
  ROUND(AVG(CAST(readmit_30d AS FLOAT64)) * 100, 2) AS readmission_30d_pct
FROM final_data
GROUP BY tertile_num
ORDER BY tertile_num;