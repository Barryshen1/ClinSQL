WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE 
      WHEN di.icd_version = 9 AND di.icd_code IN ('430', '431', '432') THEN 1
      WHEN di.icd_version = 10 AND di.icd_code IN ('I60', 'I61', 'I62') THEN 1
      ELSE 0 
    END AS is_hemorrhagic_stroke
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

serotonergic_drugs AS (
  SELECT DISTINCT LOWER(drug_name) AS drug_name
  FROM UNNEST([
    'fluoxetine', 'sertraline', 'citalopram', 'escitalopram', 'paroxetine', 'fluvoxamine',
    'venlafaxine', 'duloxetine',
    'amitriptyline', 'clomipramine', 'imipramine', 'nortriptyline',
    'tramadol', 'dextromethorphan', 'meperidine', 'pethidine',
    'sumatriptan', 'rizatriptan', 'zolmitriptan',
    'mirtazapine', 'trazodone',
    'linezolid', 'mdma'
  ]) AS drug_name
),

medication_complexity AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS serotonergic_drug_count
  FROM cohort c
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  INNER JOIN serotonergic_drugs sd
    ON LOWER(pr.drug) = sd.drug_name
  GROUP BY c.subject_id, c.hadm_id
),

cohort_with_complexity AS (
  SELECT 
    c.*,
    COALESCE(mc.serotonergic_drug_count, 0) AS serotonergic_drug_count,
    CASE 
      WHEN COALESCE(mc.serotonergic_drug_count, 0) >= 2 THEN 1 
      ELSE 0 
    END AS has_ge2_serotonergic,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort c
  LEFT JOIN medication_complexity mc
    ON c.subject_id = mc.subject_id AND c.hadm_id = mc.hadm_id
),

quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY serotonergic_drug_count) AS complexity_quartile
  FROM cohort_with_complexity
)

SELECT 
  'Hemorrhagic Stroke vs Control' AS comparison_group,
  is_hemorrhagic_stroke AS group_label,
  AVG(serotonergic_drug_count) AS mean_serotonergic_drugs,
  AVG(CAST(has_ge2_serotonergic AS FLOAT64)) AS pct_ge2_serotonergic,
  AVG(los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM quartiles
GROUP BY is_hemorrhagic_stroke

UNION ALL

SELECT 
  '≥2 vs <2 Serotonergic Drugs' AS comparison_group,
  has_ge2_serotonergic AS group_label,
  AVG(serotonergic_drug_count) AS mean_serotonergic_drugs,
  1.0 AS pct_ge2_serotonergic,  -- By definition, 100% in ≥2 group, 0% in <2
  AVG(los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM quartiles
GROUP BY has_ge2_serotonergic

UNION ALL

SELECT 
  'Top Complexity Quartile (Q4)' AS comparison_group,
  complexity_quartile AS group_label,
  AVG(serotonergic_drug_count) AS mean_serotonergic_drugs,
  AVG(CAST(has_ge2_serotonergic AS FLOAT64)) AS pct_ge2_serotonergic,
  AVG(los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM quartiles
WHERE complexity_quartile = 4
GROUP BY complexity_quartile
ORDER BY comparison_group, group_label;