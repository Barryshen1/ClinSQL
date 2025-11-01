WITH patients_filtered AS (
  SELECT p.subject_id, p.anchor_age, p.anchor_year, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'M'
),
admissions_filtered AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 45 AND 55
),
diabetes_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E08','E09','E10','E11','E12','E13'))
    OR (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('250')) -- 250.xx diabetes
  )
),
hf_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I50') OR icd_code IN ('I110','I130','I132')))
    OR (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('428') OR icd_code IN ('40201','40401','40403','40411','40413')))
  )
),
admissions_with_conditions AS (
  SELECT a.hadm_id
  FROM admissions_filtered a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diab
    ON a.hadm_id = diab.hadm_id
  INNER JOIN diabetes_codes dc ON diab.icd_code = dc.icd_code AND diab.icd_version = dc.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd hf
    ON a.hadm_id = hf.hadm_id
  INNER JOIN hf_codes hfc ON hf.icd_code = hfc.icd_code AND hf.icd_version = hfc.icd_version
  GROUP BY a.hadm_id
),
antidiabetics AS (
  SELECT p.hadm_id, p.starttime, p.drug
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN admissions_with_conditions a ON p.hadm_id = a.hadm_id
  WHERE p.starttime IS NOT NULL
    AND LOWER(p.drug) NOT LIKE '%topical%'
    AND LOWER(p.drug) NOT LIKE '%cream%'
    AND LOWER(p.drug) NOT LIKE '%lotion%'
    AND LOWER(p.drug) NOT LIKE '%ophthalmic%'
    AND LOWER(p.drug) NOT LIKE '%otic%'
),
classified_drugs AS (
  SELECT hadm_id, starttime,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(drug) IN (
        'metformin', 'glipizide', 'glyburide', 'glimepiride',
        'sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin',
        'empagliflozin', 'dapagliflozin', 'canagliflozin',
        'pioglitazone', 'rosiglitazone',
        'glipizide xl', 'glyburide micronized',
        'metformin er', 'metformin xr'
      ) OR LOWER(drug) LIKE '%metformin%' 
        OR LOWER(drug) LIKE '%gliptin%'
        OR LOWER(drug) LIKE '%gliflozin%'
        OR LOWER(drug) LIKE '%glitazone%'
        OR LOWER(drug) LIKE '%sulfonylurea%'
        THEN 'oral'
      ELSE NULL
    END AS drug_class
  FROM antidiabetics
),
first_initiation AS (
  SELECT hadm_id, drug_class, MIN(starttime) AS first_start
  FROM classified_drugs
  WHERE drug_class IS NOT NULL
  GROUP BY hadm_id, drug_class
),
time_windows AS (
  SELECT a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admittime + INTERVAL '12' HOUR AS first_12h_end,
    a.dischtime - INTERVAL '72' HOUR AS final_72h_start
  FROM admissions_filtered a
  INNER JOIN admissions_with_conditions ac ON a.hadm_id = ac.hadm_id
),
initiation_flags AS (
  SELECT fi.hadm_id, fi.drug_class,
    MAX(CASE WHEN fi.first_start >= tw.admittime AND fi.first_start <= tw.first_12h_end THEN 1 ELSE 0 END) AS initiated_first_12h,
    MAX(CASE WHEN fi.first_start >= tw.final_72h_start AND fi.first_start <= tw.dischtime THEN 1 ELSE 0 END) AS initiated_final_72h
  FROM first_initiation fi
  INNER JOIN time_windows tw ON fi.hadm_id = tw.hadm_id
  GROUP BY fi.hadm_id, fi.drug_class
),
aggregated AS (
  SELECT
    drug_class,
    AVG(initiated_first_12h) * 100 AS first_12h_pct,
    AVG(initiated_final_72h) * 100 AS final_72h_pct,
    (AVG(initiated_first_12h) - AVG(initiated_final_72h)) * 100 AS risk_diff
  FROM initiation_flags
  GROUP BY drug_class
)
SELECT
  drug_class,
  first_12h_pct,
  final_72h_pct,
  risk_diff
FROM aggregated
ORDER BY drug_class;