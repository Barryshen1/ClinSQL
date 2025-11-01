WITH patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 81 AND 91
),
aki_admissions AS (
  SELECT 
    pf.subject_id,
    pf.hadm_id,
    pf.admittime,
    pf.dischtime,
    pf.hospital_expire_flag,
    pf.age_at_admission
  FROM patients_filtered pf
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    WHERE d.hadm_id = pf.hadm_id
      AND d.icd_version = 10
      AND d.icd_code LIKE 'N17%'
  )
),
drug_exposure AS (
  SELECT 
    a.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity,
    MAX(CASE WHEN pr.drug IN ('MORPHINE', 'FENTANYL', 'HYDROMORPHONE', 'OXYCODONE', 'MIDAZOLAM', 'DIAZEPAM', 'LORAZEPAM', 'ALPRAZOLAM', 'PHENOBARBITAL', 'PROPOFOL', 'ETOMIDATE') THEN 1 ELSE 0 END) AS has_cns,
    MAX(CASE WHEN pr.drug IN ('IBUPROFEN', 'CELECOXIB', 'INDOMETHACIN', 'VANCOMYCIN', 'AMIKACIN', 'GENTAMICIN', 'TOBRAMYCIN', 'CEFOXITIN', 'ACICLOVIR', 'AMPHOTERICIN B', 'CYCLOSPORINE', 'TACROLIMUS') THEN 1 ELSE 0 END) AS has_nephro
  FROM aki_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON a.hadm_id = pr.hadm_id
  GROUP BY a.hadm_id
),
base AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    -- Compute LOS in days (precise decimal)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days,
    COALESCE(de.complexity, 0) AS complexity,
    COALESCE(de.has_cns, 0) AS has_cns,
    COALESCE(de.has_nephro, 0) AS has_nephro,
    CASE 
      WHEN COALESCE(de.has_cns, 0) = 1 AND COALESCE(de.has_nephro, 0) = 1 THEN 'both'
      ELSE 'other'
    END AS drug_group
  FROM aki_admissions a
  LEFT JOIN drug_exposure de
    ON a.hadm_id = de.hadm_id
),
group_quartiles AS (
  SELECT
    drug_group,
    APPROX_QUANTILES(complexity, 1000)[OFFSET(250)] AS q25,
    APPROX_QUANTILES(complexity, 1000)[OFFSET(500)] AS q50,
    APPROX_QUANTILES(complexity, 1000)[OFFSET(750)] AS q75
  FROM base
  GROUP BY drug_group
),
base_with_q75 AS (
  SELECT 
    b.*,
    g.q75
  FROM base b
  JOIN group_quartiles g ON b.drug_group = g.drug_group
),
base_with_top AS (
  SELECT 
    *,
    complexity >= q75 AS in_top_quartile
  FROM base_with_q75
)
SELECT
  b.drug_group,
  g.q25, 
  g.q50, 
  g.q75,
  AVG(b.complexity) AS mean_complexity,
  AVG(b.los_days) AS overall_los,
  AVG(b.hospital_expire_flag) AS overall_mortality,
  AVG(IF(b.in_top_quartile, b.los_days, NULL)) AS top_quartile_los,
  AVG(IF(b.in_top_quartile, b.hospital_expire_flag, NULL)) AS top_quartile_mortality
FROM base_with_top b
JOIN group_quartiles g ON b.drug_group = g.drug_group
GROUP BY b.drug_group, g.q25, g.q50, g.q75;