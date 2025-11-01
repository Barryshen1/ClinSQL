WITH dka_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250\.1')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E1[013]\.1'))
),
aki_codes AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^584')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N17'))
),
ards_codes AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '518.82') OR
    (icd_version = 10 AND icd_code = 'J80')
),
cohort_base AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pt.gender,
    pt.anchor_age,
    pt.anchor_year,
    pt.dod,
    -- Simplified age calculation using year extraction
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
),
dka_cohort AS (
  SELECT 
    cb.*,
    1 AS is_dka
  FROM cohort_base cb
  WHERE 
    age_at_admission BETWEEN 59 AND 69
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN dka_codes ON 
        diag.icd_code = dka_codes.icd_code AND 
        diag.icd_version = dka_codes.icd_version
      WHERE diag.hadm_id = cb.hadm_id
    )
),
control_cohort AS (
  SELECT 
    cb.*,
    0 AS is_dka
  FROM cohort_base cb
  WHERE 
    age_at_admission BETWEEN 59 AND 69
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN dka_codes ON 
        diag.icd_code = dka_codes.icd_code AND 
        diag.icd_version = dka_codes.icd_version
      WHERE diag.hadm_id = cb.hadm_id
    )
),
combined_cohorts AS (
  SELECT * FROM dka_cohort
  UNION ALL
  SELECT * FROM control_cohort
),
cohort_outcomes AS (
  SELECT 
    cc.*,
    -- 30-day mortality using existing dod from base CTE
    CASE 
      WHEN cc.dod IS NOT NULL AND 
           DATE_DIFF(CAST(cc.dod AS DATE), CAST(cc.admittime AS DATE), DAY) <= 30 
      THEN 1 
      ELSE 0 
    END AS mortality_30d,
    -- AKI flag
    CASE WHEN EXISTS (SELECT 1 FROM aki_codes aki WHERE aki.hadm_id = cc.hadm_id) 
         THEN 1 ELSE 0 END AS aki,
    -- ARDS flag
    CASE WHEN EXISTS (SELECT 1 FROM ards_codes ards WHERE ards.hadm_id = cc.hadm_id) 
         THEN 1 ELSE 0 END AS ards,
    -- Survivor LOS (only if survived hospitalization)
    CASE WHEN cc.hospital_expire_flag = 0 
         THEN DATE_DIFF(CAST(cc.dischtime AS DATE), CAST(cc.admittime AS DATE), DAY) 
         END AS survivor_los
  FROM combined_cohorts cc
  -- Removed redundant patient table join (dod already in cc)
),
final_aggregation AS (
  SELECT 
    is_dka,
    COUNT(*) AS num_patients,
    AVG(mortality_30d) AS mortality_30d_rate,
    AVG(aki) AS aki_rate,
    AVG(ards) AS ards_rate,
    AVG(survivor_los) AS avg_survivor_los_days
  FROM cohort_outcomes
  GROUP BY is_dka
)
SELECT * FROM final_aggregation;