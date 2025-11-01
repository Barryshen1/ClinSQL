WITH categorized_admissions AS (
  SELECT 
    a.hadm_id,
    CASE 
      WHEN a.admission_type = 'elective' THEN NULL  -- Excluding elective admissions as per the question
      ELSE 
        CASE 
          WHEN EXTRACT(DAY FROM a.dischtime - a.admittime) BETWEEN 1 AND 4 THEN '1-4 days'
          WHEN EXTRACT(DAY FROM a.dischtime - a.admittime) BETWEEN 5 AND 8 THEN '5-8 days'
        END
    END AS stay_duration_category,
    COALESCE(p.num_procedures, 0) AS num_procedures
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN (
    SELECT 
      hadm_id, 
      COUNT(icd_code) AS num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY 
      hadm_id
  ) p ON a.hadm_id = p.hadm_id
  WHERE 
    a.admission_type IN ('emergency', 'urgent', 'trauma')  -- Considering only emergency, urgent, and trauma admissions
    AND a.admit_provider_id IS NOT NULL
    AND EXTRACT(DAY FROM a.dischtime - a.admittime) BETWEEN 1 AND 8
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.patients` p
      JOIN 
        `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
      WHERE 
        p.anchor_age BETWEEN 53 AND 63
        AND p.gender = 'F'
    )
)
SELECT 
  stay_duration_category,
  PERCENTILE_CONT(0.25)(num_procedures) OVER (PARTITION BY stay_duration_category) AS p25,
  PERCENTILE_CONT(0.5)(num_procedures) OVER (PARTITION BY stay_duration_category) AS p50,
  PERCENTILE_CONT(0.75)(num_procedures) OVER (PARTITION BY stay_duration_category) AS p75
FROM 
  categorized_admissions
WHERE 
  stay_duration_category IS NOT NULL;