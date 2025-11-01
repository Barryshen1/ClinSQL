with chronic complications
            WHEN (d.icd_version = 9 AND (d.icd_code LIKE '2502%' OR d.icd_code LIKE '2503%' OR d.icd_code LIKE '2504%' OR d.icd_code LIKE '2505%' OR d.icd_code LIKE '2506%' OR d.icd_code LIKE '2507%')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'E115%' OR d.icd_code LIKE 'E116%' OR d.icd_code LIKE 'E117%' OR d.icd_code LIKE 'E118%' OR d.icd_code LIKE 'E119%')) THEN 2
            -- Any malignancy
            WHEN (d.icd_version = 9 AND (d.icd_code LIKE '140%' OR ... )) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'C0%' OR ... )) THEN 2
            -- Metastatic solid tumor
            WHEN (d.icd_version = 9 AND (d.icd_code LIKE '196%' OR d.icd_code LIKE '197%' OR d.icd_code LIKE '198%' OR d.icd_code LIKE '199%')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%' OR d.icd_code LIKE 'C80%')) THEN 6
            ELSE 0
          END AS weight
        FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
        WHERE d.hadm_id = lc.hadm_id
      )
      -- Remove GROUP BY 1
    ), 0) AS charlson_score
  FROM 
    los_calc lc
),;