WITH eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),

eligible_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  WHERE DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 36
),

diabetes_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (LOWER(long_title) LIKE '%diabetes%' 
         OR SUBSTR(TRIM(icd_code), 1, 3) = '250'
         OR SUBSTR(TRIM(icd_code), 1, 3) = 'E11'
         OR SUBSTR(TRIM(icd_code), 1, 3) = 'E10')
    AND icd_version IN (9, 10)
),

acute_hf_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (LOWER(long_title) LIKE '%acute heart failure%'
         OR LOWER(long_title) LIKE '%heart failure, acute%'
         OR LOWER(long_title) LIKE '%acute on chronic heart failure%'
         OR LOWER(long_title) LIKE '%decompensated heart failure%')
    AND icd_version IN (9, 10)
),

admissions_with_diabetes AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN diabetes_codes dc 
    ON TRIM(di.icd_code) = TRIM(dc.icd_code) AND di.icd_version = dc.icd_version
  GROUP BY di.hadm_id
),

admissions_with_hf AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN acute_hf_codes hf 
    ON TRIM(di.icd_code) = TRIM(hf.icd_code) AND di.icd_version = hf.icd_version
  GROUP BY di.hadm_id
),

admissions_with_both AS (
  SELECT ea.hadm_id, ea.admittime, ea.dischtime
  FROM eligible_admissions ea
  INNER JOIN admissions_with_diabetes ad ON ea.hadm_id = ad.hadm_id
  INNER JOIN admissions_with_hf ahf ON ea.hadm_id = ahf.hadm_id
),

glp1_drugs AS (
  SELECT 'liraglutide' AS drug_name
  UNION ALL SELECT 'dulaglutide'
  UNION ALL SELECT 'semaglutide'
),

injectable_routes AS (
  SELECT 'Subcutaneous' AS route_name
  UNION ALL SELECT 'SC'
  UNION ALL SELECT 'Inj'
  UNION ALL SELECT 'SQ'
  UNION ALL SELECT 'Sub-Q'
  UNION ALL SELECT 'Injection'
),

glp1_prescriptions AS (
  SELECT p.hadm_id, p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  CROSS JOIN glp1_drugs g
  CROSS JOIN injectable_routes r
  WHERE LOWER(p.drug) LIKE '%' || LOWER(g.drug_name) || '%'
    AND LOWER(p.route) LIKE '%' || LOWER(r.route_name) || '%'
    AND p.starttime IS NOT NULL
),

first_24h_starts AS (
  SELECT DISTINCT ab.hadm_id
  FROM admissions_with_both ab
  INNER JOIN glp1_prescriptions gp ON ab.hadm_id = gp.hadm_id
  WHERE gp.starttime >= ab.admittime
    AND gp.starttime <= DATETIME_ADD(ab.admittime, INTERVAL 24 HOUR)
),

final_12h_starts AS (
  SELECT DISTINCT ab.hadm_id
  FROM admissions_with_both ab
  INNER JOIN glp1_prescriptions gp ON ab.hadm_id = gp.hadm_id
  WHERE gp.starttime >= DATETIME_SUB(ab.dischtime, INTERVAL 12 HOUR)
    AND gp.starttime <= ab.dischtime
),

cohort_stats AS (
  SELECT
    COUNT(*) AS total_eligible,
    COUNT(f24.hadm_id) AS started_first_24h,
    COUNT(f12.hadm_id) AS started_final_12h
  FROM admissions_with_both ab
  LEFT JOIN first_24h_starts f24 ON ab.hadm_id = f24.hadm_id
  LEFT JOIN final_12h_starts f12 ON ab.hadm_id = f12.hadm_id
)

SELECT
  IF(total_eligible > 0, ROUND(100.0 * started_first_24h / total_eligible, 2), 0) AS first_24h_pct,
  IF(total_eligible > 0, ROUND(100.0 * started_final_12h / total_eligible, 2), 0) AS final_12h_pct
FROM cohort_stats;