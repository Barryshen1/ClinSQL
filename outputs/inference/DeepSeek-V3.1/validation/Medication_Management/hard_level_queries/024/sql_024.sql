WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND diag.icd_code = 'T07'  -- Unspecified multiple injuries (ICD-10)
    AND diag.icd_version = 10
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag, pat.anchor_age
),

first_24h_drugs AS (
  SELECT 
    c.hadm_id,
    pr.drug,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%sertraline%' OR
           LOWER(pr.drug) LIKE '%fluoxetine%' OR
           LOWER(pr.drug) LIKE '%paroxetine%' OR
           LOWER(pr.drug) LIKE '%citalopram%' OR
           LOWER(pr.drug) LIKE '%escitalopram%' OR
           LOWER(pr.drug) LIKE '%fluvoxamine%' OR
           LOWER(pr.drug) LIKE '%venlafaxine%' OR
           LOWER(pr.drug) LIKE '%duloxetine%' OR
           LOWER(pr.drug) LIKE '%tramadol%' OR
           LOWER(pr.drug) LIKE '%meperidine%' OR
           LOWER(pr.drug) LIKE '%fentanyl%' OR  -- Note: fentanyl has weak serotonergic effect
           LOWER(pr.drug) LIKE '%linezolid%' OR
           LOWER(pr.drug) LIKE '%trazodone%' OR
           LOWER(pr.drug) LIKE '%amitriptyline%' OR
           LOWER(pr.drug) LIKE '%clomipramine%' OR
           LOWER(pr.drug) LIKE '%imipramine%' OR
           LOWER(pr.drug) LIKE '%doxepin%' OR
           LOWER(pr.drug) LIKE '%mirtazapine%' OR
           LOWER(pr.drug) LIKE '%bupropion%'   -- Weak effect
      THEN 1
      ELSE 0
    END AS is_serotonergic
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE DATETIME_DIFF(pr.starttime, c.admittime, HOUR) <= 24
),

med_complexity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS num_drugs,
    SUM(is_serotonergic) AS num_serotonergic_drugs
  FROM first_24h_drugs
  GROUP BY hadm_id
),

cohort_with_complexity AS (
  SELECT
    c.*,
    COALESCE(mc.num_drugs, 0) AS num_drugs,
    COALESCE(mc.num_serotonergic_drugs, 0) AS num_serotonergic_drugs,
    CASE WHEN COALESCE(mc.num_serotonergic_drugs, 0) >= 2 THEN 1 ELSE 0 END AS has_serotonergic_risk
  FROM cohort c
  LEFT JOIN med_complexity mc
    ON c.hadm_id = mc.hadm_id
),

quartiles AS (
  SELECT
    hadm_id,
    num_drugs,
    has_serotonergic_risk,
    los_days,
    hospital_expire_flag,
    PERCENTILE_CONT(num_drugs, 0.25) OVER() AS q1,
    PERCENTILE_CONT(num_drugs, 0.5) OVER() AS median,
    PERCENTILE_CONT(num_drugs, 0.75) OVER() AS q3,
    PERCENT_RANK() OVER (ORDER BY num_drugs) AS complexity_percentile
  FROM cohort_with_complexity
)

SELECT
  'Serotonergic risk group' AS group_label,
  COUNT(*) AS n,
  APPROX_QUANTILES(num_drugs, 4) AS complexity_quartiles,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quartiles
WHERE has_serotonergic_risk = 1

UNION ALL

SELECT
  'Other multi-trauma patients' AS group_label,
  COUNT(*) AS n,
  APPROX_QUANTILES(num_drugs, 4) AS complexity_quartiles,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quartiles
WHERE has_serotonergic_risk = 0

UNION ALL

SELECT
  'Top complexity quartile' AS group_label,
  COUNT(*) AS n,
  APPROX_QUANTILES(num_drugs, 4) AS complexity_quartiles,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quartiles
WHERE num_drugs >= (SELECT DISTINCT q3 FROM quartiles LIMIT 1);