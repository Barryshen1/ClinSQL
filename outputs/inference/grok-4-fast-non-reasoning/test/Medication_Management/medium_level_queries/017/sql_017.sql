WITH cohort AS (
  -- Select qualifying admissions with ICU stays >=144h
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    i.los AS stay_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND i.los >= 144  -- >=144h
    AND (
      -- Diabetes: Ensure at least one qualifying diagnosis
      EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd2 
          ON d2.icd_code = icd2.icd_code AND d2.icd_version = icd2.icd_version
        WHERE d2.subject_id = a.subject_id AND d2.hadm_id = a.hadm_id
          AND (
            (d2.icd_version = 'ICD-9' AND d2.icd_code LIKE '250.%' AND d2.icd_code NOT LIKE '250.0[13]%') OR
            (d2.icd_version = 'ICD-10' AND (d2.icd_code LIKE 'E1[0-3]%' OR d2.icd_code LIKE 'E08%' OR d2.icd_code LIKE 'E09%'))
          )
          AND LOWER(icd2.long_title) LIKE '%diabetes%'
      )
    )
    AND (
      -- Heart failure: Ensure at least one qualifying diagnosis
      EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd3 
          ON d3.icd_code = icd3.icd_code AND d3.icd_version = icd3.icd_version
        WHERE d3.subject_id = a.subject_id AND d3.hadm_id = a.hadm_id
          AND (
            (d3.icd_version = 'ICD-9' AND d3.icd_code LIKE '428%') OR
            (d3.icd_version = 'ICD-10' AND d3.icd_code LIKE 'I50%')
          )
          AND (LOWER(icd3.long_title) LIKE '%heart failure%' OR LOWER(icd3.long_title) LIKE '%cardiac failure%')
      )
    )
),

drug_presence AS (
  -- Flag if patient has qualifying Rx overlapping first/final 72h
  SELECT 
    c.subject_id,
    c.hadm_id,
    -- First 72h: admittime to admittime + 72h
    MAX(CASE WHEN (
      LOWER(pr.drug) IN ('metformin', 'glipizide', 'glimepiride', 'sitagliptin', 'glyburide', 'empagliflozin', 'canagliflozin') OR
      LOWER(pr.drug) LIKE 'insulin%'
    ) AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
       AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
    THEN 1 ELSE 0 END) AS antidiabetic_first,
    -- Final 72h: dischtime - 72h to dischtime
    MAX(CASE WHEN (
      LOWER(pr.drug) IN ('metformin', 'glipizide', 'glimepiride', 'sitagliptin', 'glyburide', 'empagliflozin', 'canagliflozin') OR
      LOWER(pr.drug) LIKE 'insulin%'
    ) AND pr.starttime < c.dischtime
       AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR))
    THEN 1 ELSE 0 END) AS antidiabetic_final,
    -- Beta-blockers first
    MAX(CASE WHEN LOWER(pr.drug) IN (
      'metoprolol', 'atenolol', 'carvedilol', 'bisoprolol', 'propranolol', 'labetalol', 'nebivolol'
    ) AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
       AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
    THEN 1 ELSE 0 END) AS beta_first,
    -- Beta-blockers final
    MAX(CASE WHEN LOWER(pr.drug) IN (
      'metoprolol', 'atenolol', 'carvedilol', 'bisoprolol', 'propranolol', 'labetalol', 'nebivolol'
    ) AND pr.starttime < c.dischtime
       AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR))
    THEN 1 ELSE 0 END) AS beta_final,
    -- ACEi/ARB/ARNI first
    MAX(CASE WHEN LOWER(pr.drug) IN (
      'lisinopril', 'ramipril', 'enalapril', 'losartan', 'valsartan', 'candesartan', 'sacubitril%'
    ) AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
       AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
    THEN 1 ELSE 0 END) AS acearb_first,
    -- ACEi/ARB/ARNI final
    MAX(CASE WHEN LOWER(pr.drug) IN (
      'lisinopril', 'ramipril', 'enalapril', 'losartan', 'valsartan', 'candesartan', 'sacubitril%'
    ) AND pr.starttime < c.dischtime
       AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR))
    THEN 1 ELSE 0 END) AS acearb_final,
    -- Loop diuretics first
    MAX(CASE WHEN LOWER(pr.drug) IN (
      'furosemide', 'bumetanide', 'torsemide'
    ) AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
       AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
    THEN 1 ELSE 0 END) AS loop_first,
    -- Loop diuretics final
    MAX(CASE WHEN LOWER(pr.drug) IN (
      'furosemide', 'bumetanide', 'torsemide'
    ) AND pr.starttime < c.dischtime
       AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR))
    THEN 1 ELSE 0 END) AS loop_final
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
    AND pr.starttime < c.dischtime 
    AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
  GROUP BY c.subject_id, c.hadm_id
),

changes AS (
  SELECT 
    subject_id,
    hadm_id,
    -- Antidiabetics
    antidiabetic_first,
    antidiabetic_final,
    CASE 
      WHEN antidiabetic_first = 1 AND antidiabetic_final = 1 THEN 'Continued'
      WHEN antidiabetic_first = 0 AND antidiabetic_final = 1 THEN 'Initiated'
      WHEN antidiabetic_first = 1 AND antidiabetic_final = 0 THEN 'Discontinued'
      ELSE 'Never'
    END AS antidiabetic_change,
    -- Beta-blockers
    beta_first,
    beta_final,
    CASE 
      WHEN beta_first = 1 AND beta_final = 1 THEN 'Continued'
      WHEN beta_first = 0 AND beta_final = 1 THEN 'Initiated'
      WHEN beta_first = 1 AND beta_final = 0 THEN 'Discontinued'
      ELSE 'Never'
    END AS beta_change,
    -- ACEi/ARB/ARNI
    acearb_first,
    acearb_final,
    CASE 
      WHEN acearb_first = 1 AND acearb_final = 1 THEN 'Continued'
      WHEN acearb_first = 0 AND acearb_final = 1 THEN 'Initiated'
      WHEN acearb_first = 1 AND acearb_final = 0 THEN 'Discontinued'
      ELSE 'Never'
    END AS acearb_change,
    -- Loop diuretics
    loop_first,
    loop_final,
    CASE 
      WHEN loop_first = 1 AND loop_final = 1 THEN 'Continued'
      WHEN loop_first = 0 AND loop_final = 1 THEN 'Initiated'
      WHEN loop_first = 1 AND loop_final = 0 THEN 'Discontinued'
      ELSE 'Never'
    END AS loop_change
  FROM drug_presence
)

-- Summary: % on meds and change counts
SELECT 
  'Antidiabetics' AS medication,
  ROUND(AVG(antidiabetic_first) * 100, 1) AS pct_first_72h,
  ROUND(AVG(antidiabetic_final) * 100, 1) AS pct_final_72h,
  COUNT(CASE WHEN antidiabetic_change = 'Continued' THEN 1 END) AS continued,
  COUNT(CASE WHEN antidiabetic_change = 'Initiated' THEN 1 END) AS initiated,
  COUNT(CASE WHEN antidiabetic_change = 'Discontinued' THEN 1 END) AS discontinued,
  COUNT(*) AS total_patients
FROM changes
UNION ALL
SELECT 
  'Beta-blockers' AS medication,
  ROUND(AVG(beta_first) * 100, 1) AS pct_first_72h,
  ROUND(AVG(beta_final) * 100, 1) AS pct_final_72h,
  COUNT(CASE WHEN beta_change = 'Continued' THEN 1 END) AS continued,
  COUNT(CASE WHEN beta_change = 'Initiated' THEN 1 END) AS initiated,
  COUNT(CASE WHEN beta_change = 'Discontinued' THEN 1 END) AS discontinued,
  COUNT(*) AS total_patients
FROM changes
UNION ALL
SELECT 
  'ACEi/ARB/ARNI' AS medication,
  ROUND(AVG(acearb_first) * 100, 1) AS pct_first_72h,
  ROUND(AVG(acearb_final) * 100, 1) AS pct_final_72h,
  COUNT(CASE WHEN acearb_change = 'Continued' THEN 1 END) AS continued,
  COUNT(CASE WHEN acearb_change = 'Initiated' THEN 1 END) AS initiated,
  COUNT(CASE WHEN acearb_change = 'Discontinued' THEN 1 END) AS discontinued,
  COUNT(*) AS total_patients
FROM changes
UNION ALL
SELECT 
  'Loop diuretics' AS medication,
  ROUND(AVG(loop_first) * 100, 1) AS pct_first_72h,
  ROUND(AVG(loop_final) * 100, 1) AS pct_final_72h,
  COUNT(CASE WHEN loop_change = 'Continued' THEN 1 END) AS continued,
  COUNT(CASE WHEN loop_change = 'Initiated' THEN 1 END) AS initiated,
  COUNT(CASE WHEN loop_change = 'Discontinued' THEN 1 END) AS discontinued,
  COUNT(*) AS total_patients
FROM changes
ORDER BY medication;