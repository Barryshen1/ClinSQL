WITH 
  -- Define necessary CTEs here, for example:
  patient_data AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      icu.stay_id,
      icu.icu_los,
      CASE 
        WHEN adm.hospital_expire_flag = 1 THEN 1 
        ELSE 0 
      END AS mortality
    FROM 
      `physionet-data.mimiciv_3_1_hosp`.patients p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp`.admissions adm ON p.subject_id = adm.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu`.icustays icu ON adm.hadm_id = icu.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 55 AND 65
      AND adm.diagnoses_icd.icd_code LIKE '481%'
  ),
  instability_scores AS (
    -- Calculation of instability score, for demonstration
    SELECT 
      subject_id,
      stay_id,
      60 AS instability_score, -- Example score
      icu_los,
      mortality
    FROM 
      patient_data
  )

-- Calculate percentile and report ICU LOS and mortality for the most unstable decile
SELECT 
  instability_decile,
  MIN(instability_score) AS min_score,
  MAX(instability_score) AS max_score,
  AVG(icu_los) AS avg_icu_los,
  AVG(mortality) AS avg_mortality
FROM (
  SELECT 
    instability_score,
    icu_los,
    mortality,
    NTILE(10) OVER (ORDER BY instability_score) AS instability_decile
  FROM 
    instability_scores
) AS subquery
GROUP BY 
  instability_decile
ORDER BY 
  instability_decile;