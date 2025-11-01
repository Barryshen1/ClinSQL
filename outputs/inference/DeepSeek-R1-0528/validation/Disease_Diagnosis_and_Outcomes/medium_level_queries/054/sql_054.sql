WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) <= 3 THEN 'LOS≤3'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 6 THEN 'LOS4-6'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 7 AND 10 THEN 'LOS7-10'
      ELSE 'LOS>10' 
    END AS los_category,
    EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
      WHERE icu.hadm_id = adm.hadm_id
    ) AS is_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M' 
    AND pat.anchor_age = 44
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
      WHERE proc.hadm_id = adm.hadm_id
    )
),

charlson AS (
  SELECT 
    hadm_id,
    SUM(weight) AS charlson_score
  FROM (
    SELECT 
      diag.hadm_id,
      CASE 
        WHEN diag.icd_code LIKE '410%' OR diag.icd_code LIKE '411%' OR diag.icd_code IN ('I21', 'I22', 'I252', 'I50') THEN 1  -- MI, CHF
        WHEN diag.icd_code LIKE '428%' OR diag.icd_code IN ('I099', 'I110', 'I130', 'I132', 'I255', 'I420', 'I425', 'I426', 'I427', 'I428', 'I429', 'P290') THEN 1
        WHEN diag.icd_code LIKE '430%' OR diag.icd_code LIKE '431%' OR diag.icd_code LIKE '432%' OR diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR diag.icd_code LIKE '435%' OR diag.icd_code LIKE '436%' OR diag.icd_code LIKE '437%' OR diag.icd_code LIKE '438%' OR diag.icd_code IN ('G45', 'G46', 'I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') THEN 1
        WHEN diag.icd_code LIKE '440%' OR diag.icd_code LIKE '441%' OR diag.icd_code LIKE '442%' OR diag.icd_code LIKE '443%' OR diag.icd_code LIKE '444%' OR diag.icd_code LIKE '445%' OR diag.icd_code IN ('I70', 'I71', 'I731', 'I738', 'I739', 'I771', 'I790', 'I792', 'K551', 'K558', 'K559', 'Z958', 'Z959') THEN 1
        WHEN diag.icd_code IN ('2900', '2901', '2902', '2903', '2904', '2941', '3312') OR diag.icd_code LIKE 'F00%' OR diag.icd_code LIKE 'F01%' OR diag.icd_code LIKE 'F02%' OR diag.icd_code LIKE 'F03%' OR diag.icd_code IN ('F051', 'G30', 'G311') THEN 1
        WHEN diag.icd_code LIKE '490%' OR diag.icd_code LIKE '491%' OR diag.icd_code LIKE '492%' OR diag.icd_code LIKE '493%' OR diag.icd_code LIKE '494%' OR diag.icd_code LIKE '495%' OR diag.icd_code LIKE '496%' OR diag.icd_code LIKE '500%' OR diag.icd_code LIKE '501%' OR diag.icd_code LIKE '502%' OR diag.icd_code LIKE '503%' OR diag.icd_code LIKE '504%' OR diag.icd_code LIKE '505%' OR diag.icd_code IN ('J40', 'J41', 'J42', 'J43', 'J44', 'J45', 'J46', 'J47', 'J60', 'J61', 'J62', 'J63', 'J64', 'J65', 'J66', 'J67') THEN 1
        WHEN diag.icd_code IN ('25000', '25001', '25002', '25003') OR diag.icd_code LIKE '2501%' OR diag.icd_code LIKE '2502%' OR diag.icd_code LIKE '2503%' OR diag.icd_code LIKE '2504%' OR diag.icd_code LIKE '2505%' OR diag.icd_code LIKE '2506%' OR diag.icd_code LIKE '2507%' OR diag.icd_code LIKE '2508%' OR diag.icd_code LIKE '2509%' OR diag.icd_code IN ('E100', 'E101', 'E106', 'E108', 'E109', 'E110', 'E111', 'E116', 'E118', 'E119', 'E120', 'E121', 'E126', 'E128', 'E129', 'E130', 'E131', 'E136', 'E138', 'E139', 'E140', 'E141', 'E146', 'E148', 'E149') THEN 1
        WHEN diag.icd_code IN ('3420', '3421', '3422', '3423', '3424', '3425', '3426', '3427', '3428', '3429', '3430', '3431', '3432', '3433', '3434', '3438', '3439', '3440', '3441', '3442', '3443', '3444', '3445', '3446', '3449') OR diag.icd_code IN ('G81', 'G82', 'G041', 'G114', 'G801', 'G802', 'G830', 'G831', 'G832', 'G833', 'G834', 'G839') THEN 2
        WHEN diag.icd_code IN ('5820', '5821', '5822', '5824', '5828', '5829', '5830', '5831', '5832', '5834', '5836', '5837', '5880', 'V420', 'V451') OR diag.icd_code IN ('N032', 'N033', 'N034', 'N035', 'N036', 'N037', 'N052', 'N053', 'N054', 'N055', 'N056', 'N057', 'N18', 'N19', 'N250', 'Z490', 'Z491', 'Z492', 'Z940', 'Z992') THEN 2
        WHEN diag.icd_code IN ('1960', '1961', '1962', '1963', '1965', '1966', '1968', '1969', '1991') OR diag.icd_code IN ('C77', 'C78', 'C79', 'C80') THEN 6
        ELSE 0 
      END AS weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN cohort c ON diag.hadm_id = c.hadm_id
  ) 
  GROUP BY hadm_id
),

outcomes AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.los_category,
    c.is_icu,
    c.hospital_expire_flag AS mortality,
    CASE 
      WHEN ch.charlson_score <= 3 THEN 'Charlson≤3'
      WHEN ch.charlson_score BETWEEN 4 AND 5 THEN 'Charlson4-5'
      ELSE 'Charlson>5' 
    END AS charlson_category,
    -- Mechanical Ventilation
    CASE 
      WHEN c.is_icu AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        WHERE pe.hadm_id = c.hadm_id 
          AND pe.itemid IN (225468, 227194)  -- Non-invasive/Invasive Ventilation
      ) THEN 1
      WHEN NOT c.is_icu AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
        WHERE proc.hadm_id = c.hadm_id 
          AND (
            (proc.icd_version = 9 AND proc.icd_code LIKE '967%') OR 
            (proc.icd_version = 10 AND proc.icd_code IN ('5A1955Z', '5A1935Z', '5A1945Z'))
          )
      ) THEN 1
      ELSE 0 
    END AS mech_vent,
    -- Vasopressors (ICU only)
    CASE 
      WHEN c.is_icu AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie 
        WHERE ie.hadm_id = c.hadm_id 
          AND ie.itemid IN (221906, 221289, 221662, 221749, 222315)  -- Norepinephrine, Epinephrine, etc.
      ) THEN 1
      ELSE 0 
    END AS vasopressor,
    -- RRT
    CASE 
      WHEN c.is_icu AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        WHERE pe.hadm_id = c.hadm_id 
          AND pe.itemid IN (225802, 225803, 225805, 225809, 225955)  -- CRRT, CVVHD, etc.
      ) THEN 1
      WHEN NOT c.is_icu AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
        WHERE proc.hadm_id = c.hadm_id 
          AND (
            (proc.icd_version = 9 AND proc.icd_code IN ('39.95', '54.98')) OR 
            (proc.icd_version = 10 AND proc.icd_code LIKE '5A1D%')
          )
      ) THEN 1
      ELSE 0 
    END AS rrt
  FROM cohort c
  LEFT JOIN charlson ch ON c.hadm_id = ch.hadm_id
),

-- Renamed CTE (GROUPS is reserved)
grouped_data AS (
  SELECT 
    CASE WHEN is_icu THEN 'ICU' ELSE 'Non-ICU' END AS location,
    los_category,
    charlson_category,
    COUNT(*) AS total_patients,
    ROUND(100.0 * SUM(mortality) / COUNT(*), 2) AS mortality_pct,
    ROUND(100.0 * SUM(mech_vent) / COUNT(*), 2) AS mech_vent_pct,
    ROUND(100.0 * SUM(vasopressor) / COUNT(*), 2) AS vasopressor_pct,
    ROUND(100.0 * SUM(rrt) / COUNT(*), 2) AS rrt_pct
  FROM outcomes
  GROUP BY location, los_category, charlson_category
),

ref_mortality AS (
  SELECT 
    location,
    charlson_category,
    mortality_pct AS ref_mortality_pct
  FROM grouped_data
  WHERE los_category = 'LOS≤3'
)

SELECT 
  g.location,
  g.los_category,
  g.charlson_category,
  g.total_patients,
  g.mortality_pct,
  g.mortality_pct - r.ref_mortality_pct AS mortality_abs_diff,
  ROUND(100.0 * (g.mortality_pct - r.ref_mortality_pct) / NULLIF(r.ref_mortality_pct, 0), 2) AS mortality_rel_diff_pct,
  g.mech_vent_pct,
  g.vasopressor_pct,
  g.rrt_pct
FROM grouped_data g
LEFT JOIN ref_mortality r
  ON g.location = r.location 
  AND g.charlson_category = r.charlson_category
ORDER BY g.location, g.charlson_category, 
  CASE g.los_category
    WHEN 'LOS≤3' THEN 1
    WHEN 'LOS4-6' THEN 2
    WHEN 'LOS7-10' THEN 3
    ELSE 4
  END;