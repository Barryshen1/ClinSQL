WITH 
  -- Identify asthma exacerbation
  asthma_admissions AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON 
      a.hadm_id = d.hadm_id
    WHERE 
      d.icd_code LIKE '493%'  -- Asthma
      AND a.subject_id IN (
        SELECT 
          subject_id 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.patients` 
        WHERE 
          anchor_age BETWEEN 77 AND 87 
          AND gender = 'M'
      )
  ),
  
  -- Identify ICU stays
  icu_stays AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Identify CT/MRI procedures
  ct_mri_procedures AS (
    SELECT 
      hadm_id, 
      COUNT(*) as ct_mri_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE 
      icd_code LIKE '87%'  -- CT/MRI codes
    GROUP BY 
      hadm_id
  )

-- Calculate length of stay and join with CT/MRI count
SELECT 
  CASE 
    WHEN i.stay_id IS NOT NULL THEN 'ICU'
    ELSE 'Non-ICU'
  END AS care_unit,
  CASE 
    WHEN DATE_DIFF(a.dischtime, a.admittime, INTERVAL 1 DAY) BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN DATE_DIFF(a.dischtime, a.admittime, INTERVAL 1 DAY) BETWEEN 5 AND 8 THEN '5-8 days'
  END AS length_of_stay,
  AVG(c.ct_mri_count) AS mean_ct_mri,
  MIN(c.ct_mri_count) AS min_ct_mri,
  MAX(c.ct_mri_count) AS max_ct_mri
FROM 
  asthma_admissions a
  LEFT JOIN icu_stays i ON a.hadm_id = i.hadm_id
  LEFT JOIN ct_mri_procedures c ON a.hadm_id = c.hadm_id
GROUP BY 
  care_unit,
  length_of_stay;