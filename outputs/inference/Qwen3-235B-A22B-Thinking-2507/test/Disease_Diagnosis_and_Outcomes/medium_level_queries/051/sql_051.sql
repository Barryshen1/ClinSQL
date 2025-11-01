SELECT 
    a.hadm_id,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu`.icustays
  ) i ON a.hadm_id = i.hadm_id
);