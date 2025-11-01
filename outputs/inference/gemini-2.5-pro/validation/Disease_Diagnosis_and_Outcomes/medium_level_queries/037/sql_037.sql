WITH elixhauser_calculation AS (
  -- This CTE calculates the Elixhauser comorbidity count from scratch.
  -- It sums the presence of 30 different comorbidity categories.
  SELECT
    hadm_id,
    -- Each line is a MAX(CASE...) to flag if any ICD code for that comorbidity exists for the hadm_id.
    -- The sum of these flags is the total comorbidity count.
    (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('398', '402', '404') OR SUBSTR(icd_code, 1, 4) IN ('4254', '4255', '4257', '4258', '4259') OR icd_code IN ('42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833', '42840', '42841', '42842', '42843', '4289', '4281', '4280'))) OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I09', 'I11', 'I13', 'I25', 'I42', 'I43', 'I50') OR SUBSTR(icd_code, 1, 4) IN ('I255'))) THEN 1 ELSE 0 END)) -- Congestive heart failure
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('426', '427') OR SUBSTR(icd_code, 1, 4) IN ('7850') OR icd_code IN ('V450', 'V533'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I44', 'I45', 'I47', 'I48', 'I49', 'R00', 'T82', 'Z45', 'Z95')) THEN 1 ELSE 0 END)) -- Cardiac arrhythmias
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('093', '421', '424', '746') OR SUBSTR(icd_code, 1, 4) IN ('394', '395', '396', '397', '4249', 'V422', 'V433'))) OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('A52', 'I05', 'I06', 'I07', 'I08', 'I09', 'I34', 'I35', 'I36', 'I37', 'I38', 'I39', 'Q23', 'Z95') OR SUBSTR(icd_code, 1, 4) IN ('I091'))) THEN 1 ELSE 0 END)) -- Valvular disease
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('415', '416', '417', '518') OR SUBSTR(icd_code, 1, 4) IN ('5184'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I26', 'I27', 'I28', 'J95', 'J96', 'J98')) THEN 1 ELSE 0 END)) -- Pulmonary circulation
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('440', '441', '443', '447', '557') OR icd_code = '4439')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I70', 'I71', 'I73', 'I77', 'I79', 'K55')) THEN 1 ELSE 0 END)) -- Peripheral vascular
    + (MAX(CASE WHEN (icd_version = 9 AND icd_code IN ('4011', '4019', '4010')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I10')) THEN 1 ELSE 0 END)) -- Hypertension
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('334', '342', '343', '344') OR icd_code IN ('3449'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('G80', 'G81', 'G82', 'G83')) THEN 1 ELSE 0 END)) -- Paralysis
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('331', '332', '333', '335', '340', '341', '345', '348', '780', '784') OR icd_code IN ('3319', '3481', '3483', '7803', '7843'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('F01', 'F02', 'F03', 'G10', 'G11', 'G12', 'G20', 'G21', 'G22', 'G25', 'G30', 'G31', 'G32', 'G35', 'G36', 'G37', 'G40', 'G41', 'G45', 'G46', 'G90', 'G93', 'R47', 'R56')) THEN 1 ELSE 0 END)) -- Other neurological
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('490', '491', '492', '493', '494', '495', '496', '500', '501', '502', '503', '504', '505')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('J40', 'J41', 'J42', 'J43', 'J44', 'J45', 'J46', 'J47', 'J60', 'J61', 'J62', 'J63', 'J64', 'J65', 'J66', 'J67', 'J68', 'J70')) THEN 1 ELSE 0 END)) -- Chronic pulmonary
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2500', '2501', '2502', '2503')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E100', 'E101', 'E106', 'E108', 'E109', 'E110', 'E111', 'E116', 'E118', 'E119', 'E120', 'E121', 'E126', 'E128', 'E129', 'E130', 'E131', 'E136', 'E138', 'E139', 'E140', 'E141', 'E146', 'E148', 'E149')) THEN 1 ELSE 0 END)) -- Diabetes uncomplicated
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2504', '2505', '2506', '2507', '2508', '2509')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E102', 'E103', 'E104', 'E105', 'E107', 'E112', 'E113', 'E114', 'E115', 'E117', 'E122', 'E123', 'E124', 'E125', 'E127', 'E132', 'E133', 'E134', 'E135', 'E137', 'E142', 'E143', 'E144', 'E145', 'E147')) THEN 1 ELSE 0 END)) -- Diabetes complicated
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('243', '244') OR icd_code IN ('2409', '2460'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E00', 'E01', 'E02', 'E03', 'E05', 'E06', 'E07', 'E89')) THEN 1 ELSE 0 END)) -- Hypothyroidism
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('403', '585', '586') OR icd_code IN ('585', '586', 'V420', 'V451', 'V560', 'V568', 'V561', 'V562', 'V563'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I12', 'N18', 'N19', 'N25', 'Z49', 'Z94', 'Z99')) THEN 1 ELSE 0 END)) -- Renal failure
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('070', '570', '571', '572', '573') OR SUBSTR(icd_code, 1, 4) IN ('4560', '4561', '4562') OR icd_code IN ('V427'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('B15', 'B16', 'B17', 'B18', 'B19', 'I85', 'I86', 'I98', 'K70', 'K71', 'K72', 'K73', 'K74', 'K75', 'K76', 'K77', 'Z94')) THEN 1 ELSE 0 END)) -- Liver disease
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('531', '532', '533', '534')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('K25', 'K26', 'K27', 'K28')) THEN 1 ELSE 0 END)) -- Peptic ulcer
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('042', '043', '044')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('B20', 'B21', 'B22', 'B24')) THEN 1 ELSE 0 END)) -- AIDS
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('200', '201', '202') OR SUBSTR(icd_code, 1, 4) IN ('2386'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('C81', 'C82', 'C83', 'C84', 'C85', 'C86', 'C88', 'C90', 'C96')) THEN 1 ELSE 0 END)) -- Lymphoma
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('196', '197', '198', '199')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('C77', 'C78', 'C79', 'C80')) THEN 1 ELSE 0 END)) -- Metastatic cancer
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(icd_code, 1, 3) BETWEEN '174' AND '195' OR SUBSTR(icd_code, 1, 3) BETWEEN '200' AND '208' OR SUBSTR(icd_code, 1, 3) = '238' OR icd_code IN ('20970', '20971', '20972', '20973', '20974', '20975', '20979'))) OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C76' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C80' AND 'C97')) THEN 1 ELSE 0 END)) -- Solid tumor
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('701', '710', '714', '720', '725')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('L94', 'M05', 'M06', 'M07', 'M08', 'M09', 'M12', 'M30', 'M31', 'M32', 'M33', 'M34', 'M35', 'M36', 'M45', 'M46')) THEN 1 ELSE 0 END)) -- Rheumatoid arthritis
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('286', '287')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('D65', 'D66', 'D67', 'D68', 'D69')) THEN 1 ELSE 0 END)) -- Coagulopathy
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('278')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E65', 'E66', 'E67')) THEN 1 ELSE 0 END)) -- Obesity
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('260', '261', '262', '263')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E40', 'E41', 'E42', 'E43', 'E44', 'E45', 'E46')) THEN 1 ELSE 0 END)) -- Weight loss
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('276')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E86', 'E87')) THEN 1 ELSE 0 END)) -- Fluid electrolyte
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2800', '2801', '2808', '2809', '2812', '2814', '2819', '2859')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('D50', 'D51', 'D52', 'D53', 'D64')) THEN 1 ELSE 0 END)) -- Blood loss anemia
    + (MAX(CASE WHEN (icd_version = 9 AND icd_code IN ('2810', '2811', '2813')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('D50', 'D51', 'D52', 'D53')) THEN 1 ELSE 0 END)) -- Deficiency anemia
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('291', '292', '303', '304') OR SUBSTR(icd_code, 1, 4) IN ('3050', '3052', '3053', '3054', '3055', '3056', '3057', '3058', '3059'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('F10', 'F11', 'F12', 'F13', 'F14', 'F15', 'F16', 'F17', 'F18', 'F19')) THEN 1 ELSE 0 END)) -- Alcohol abuse
    + (MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('295', '296', '297', '298', '301', '309', '311') OR icd_code IN ('2990', '2991', '2998', '2999'))) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('F06', 'F20', 'F21', 'F22', 'F23', 'F24', 'F25', 'F28', 'F29', 'F30', 'F31', 'F32', 'F33', 'F34', 'F38', 'F39', 'F4', 'F5', 'F6', 'F84', 'F99')) THEN 1 ELSE 0 END)) -- Psychoses
    + (MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('290', '294', '310')) OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('F01', 'F02', 'F03', 'F04', 'F05', 'F07', 'F09', 'G30', 'G31', 'G94', 'R41')) THEN 1 ELSE 0 END)) -- Depression
    AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

sepsis_admissions AS (
  -- First, identify all hospital admissions (hadm_id) with a diagnosis of sepsis or septic shock.
  SELECT
    hadm_id,
    -- Flag for septic shock diagnosis
    MAX(CASE
      WHEN icd_version = 9 AND icd_code = '78552' THEN 1  -- Septic shock
      WHEN icd_version = 10 AND icd_code = 'R6521' THEN 1 -- Septic shock
      ELSE 0
    END) AS is_septic_shock,
    -- Flag for any sepsis diagnosis (including severe sepsis, but not necessarily shock)
    MAX(CASE
      WHEN icd_version = 9 AND icd_code IN ('99591', '99592') THEN 1 -- Sepsis, Severe sepsis
      WHEN icd_version = 10 AND icd_code LIKE 'A41%' THEN 1         -- Sepsis, various organisms
      ELSE 0
    END) AS is_sepsis
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
  -- Keep only admissions with at least one of the sepsis-related diagnoses
  HAVING
    is_septic_shock = 1 OR is_sepsis = 1
),

cohort_with_metrics AS (
  -- Construct the final cohort by joining sepsis information with patient demographics, admission details, and comorbidities.
  SELECT
    adm.hadm_id,
    adm.admission_type,
    adm.hospital_expire_flag,
    COALESCE(elix.comorbidity_count, 0) AS comorbidity_count,
    -- Define sepsis severity: if a shock code is present, it's 'Septic Shock', otherwise 'Sepsis (no shock)'
    CASE
      WHEN dx.is_septic_shock = 1 THEN 'Septic Shock'
      ELSE 'Sepsis (no shock)'
    END AS sepsis_severity,
    -- Calculate LOS in days and create categories
    CASE
      WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24) BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24) >= 8 THEN '>=8 days'
      ELSE NULL
    END AS los_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    sepsis_admissions AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN
    elixhauser_calculation AS elix
    ON adm.hadm_id = elix.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
)

-- Final aggregation and reporting
SELECT
  sepsis_severity,
  los_category,
  admission_type,
  COUNT(hadm_id) AS number_of_patients,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(comorbidity_count), 2) AS mean_comorbidity_count
FROM
  cohort_with_metrics
WHERE
  los_category IS NOT NULL -- Exclude admissions with null discharge times or zero LOS
GROUP BY
  sepsis_severity,
  los_category,
  admission_type
ORDER BY
  sepsis_severity,
  -- Custom order for LOS category to be sequential
  CASE
    WHEN los_category = '1-3 days' THEN 1
    WHEN los_category = '4-7 days' THEN 2
    WHEN los_category = '>=8 days' THEN 3
  END,
  admission_type;