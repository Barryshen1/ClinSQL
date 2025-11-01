WITH base_cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag AS mortality,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        WHERE 
          a.hadm_id = diag.hadm_id AND
          (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I6[0-2]%') OR
            (diag.icd_version = 9 AND diag.icd_code LIKE '43[0-2]%')
          )
      ) THEN 1 
      ELSE 0 
    END AS is_hemorrhagic
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

prescriptions_48h AS (
  SELECT 
    pr.hadm_id,
    pr.drug AS drug_name,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%citalopram%' OR
           LOWER(pr.drug) LIKE '%escitalopram%' OR
           LOWER(pr.drug) LIKE '%fluoxetine%' OR
           LOWER(pr.drug) LIKE '%fluvoxamine%' OR
           LOWER(pr.drug) LIKE '%paroxetine%' OR
           LOWER(pr.drug) LIKE '%sertraline%' OR
           LOWER(pr.drug) LIKE '%duloxetine%' OR
           LOWER(pr.drug) LIKE '%venlafaxine%' OR
           LOWER(pr.drug) LIKE '%desvenlafaxine%' OR
           LOWER(pr.drug) LIKE '%trazodone%' OR
           LOWER(pr.drug) LIKE '%nefazodone%' OR
           LOWER(pr.drug) LIKE '%vilazodone%' OR
           LOWER(pr.drug) LIKE '%vortioxetine%' OR
           LOWER(pr.drug) LIKE '%tramadol%' OR
           LOWER(pr.drug) LIKE '%fentanyl%' OR
           LOWER(pr.drug) LIKE '%lithium%' OR
           LOWER(pr.drug) LIKE '%buspirone%' OR
           LOWER(pr.drug) LIKE '%triptan%' OR
           LOWER(pr.drug) LIKE '%sumatriptan%' OR
           LOWER(pr.drug) LIKE '%rizatriptan%' OR
           LOWER(pr.drug) LIKE '%almotriptan%' OR
           LOWER(pr.drug) LIKE '%eletriptan%' OR
           LOWER(pr.drug) LIKE '%frovatriptan%' OR
           LOWER(pr.drug) LIKE '%naratriptan%' OR
           LOWER(pr.drug) LIKE '%zolmitriptan%' 
      THEN 1 
      ELSE 0 
    END AS is_serotonergic
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN base_cohort b
    ON pr.hadm_id = b.hadm_id
  WHERE 
    pr.starttime >= b.admittime
    AND pr.starttime <= DATETIME_ADD(b.admittime, INTERVAL 48 HOUR)
),

patient_meds AS (
  SELECT 
    b.subject_id,
    b.hadm_id,
    b.is_hemorrhagic,
    b.los_days,
    b.mortality,
    COUNT(DISTINCT p.drug_name) AS medication_complexity,
    COUNT(DISTINCT CASE WHEN p.is_serotonergic = 1 THEN p.drug_name END) AS serotonergic_count
  FROM base_cohort b
  LEFT JOIN prescriptions_48h p
    ON b.hadm_id = p.hadm_id
  GROUP BY b.subject_id, b.hadm_id, b.is_hemorrhagic, b.los_days, b.mortality
),

quartile_cutoff AS (
  SELECT 
    APPROX_QUANTILES(medication_complexity, 4)[OFFSET(3)] AS q3
  FROM patient_meds
)

SELECT 
  pm.*,
  CASE 
    WHEN pm.serotonergic_count >= 2 THEN '>=2' 
    ELSE '<2' 
  END AS serotonergic_group,
  CASE 
    WHEN pm.medication_complexity >= (SELECT q3 FROM quartile_cutoff) THEN 1
    ELSE 0 
  END AS is_top_complexity
FROM patient_meds pm;