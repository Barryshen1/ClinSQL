WITH 
  -- Define upper GI bleed ICD codes (sample codes, may need adjustment)
  upper_gi_bleed_icd_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Upper GI bleed%' OR long_title LIKE '%Gastrointestinal hemorrhage%'
  ),

  -- Select relevant admissions
  eligible_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 74 AND 84
      AND a.hadm_id IN (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE icd_code IN (SELECT icd_code FROM upper_gi_bleed_icd_codes)
        AND seq_num = 1  -- Primary diagnosis
      )
  )

-- Calculate 25th percentile LOS
SELECT 
  APPROX_QUANTILES(TIMESTAMP_DIFF(ea.dischtime, ea.admittime, DAY), 100)[OFFSET(25)] AS los_25th_percentile
FROM 
  eligible_admissions ea;