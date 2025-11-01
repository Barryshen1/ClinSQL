WITH 
  -- Define high-sensitivity troponin T itemid and categorize results
  troponin_results AS (
    SELECT 
      le.subject_id,
      le.hadm_id,
      le.valuenum,
      CASE 
        WHEN le.valuenum <= 0.014 THEN 'Normal'
        WHEN le.valuenum BETWEEN 0.015 AND 0.052 THEN 'Borderline'
        WHEN le.valuenum > 0.052 THEN 'Myocardial Injury'
        ELSE 'Unknown'
      END AS troponin_category
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
      ON le.itemid = dli.itemid
    WHERE 
      dli.label = 'High Sensitivity Troponin T'
  ),

  -- Filter patients based on age, gender, and admission type
  eligible_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 64 AND 74
      AND a.admission_type = 'acute myocardial infarction'
  )

-- Join eligible patients with troponin results and calculate percentages
SELECT 
  tr.troponin_category,
  COUNT(tr.hadm_id) AS patient_count,
  SUM(COUNT(tr.hadm_id)) OVER () AS total_patients,
  COUNT(tr.hadm_id) * 100 / SUM(COUNT(tr.hadm_id)) OVER () AS percentage
FROM 
  troponin_results tr
  JOIN eligible_patients ep 
    ON tr.subject_id = ep.subject_id AND tr.hadm_id = ep.hadm_id
GROUP BY 
  tr.troponin_category
ORDER BY 
  tr.troponin_category;