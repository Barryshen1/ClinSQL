WITH ami_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'acute myocardial infarction')
),
exclusion_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'\bshock\b') 
    OR REGEXP_CONTAINS(LOWER(long_title), r'respiratory failure')
),
base_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    adm.discharge_location,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN ami_codes 
        ON diag.icd_code = ami_codes.icd_code 
        AND diag.icd_version = ami_codes.icd_version
      WHERE diag.hadm_id = adm.hadm_id
    )
),
cohort_with_exclusions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime, 
    hospital_expire_flag,
    discharge_location,
    age_at_admission,
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS los
  FROM base_cohort
  WHERE 
    age_at_admission BETWEEN 69 AND 79
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN exclusion_codes exc
        ON diag.icd_code = exc.icd_code 
        AND diag.icd_version = exc.icd_version
      WHERE diag.hadm_id = base_cohort.hadm_id
    )
),
cohort_with_groups AS (
  SELECT 
    *,
    CASE 
      WHEN los BETWEEN 1 AND 3 THEN '1-3'
      WHEN los BETWEEN 4 AND 7 THEN '4-7'
      WHEN los >= 8 THEN '>=8'
    END AS los_group
  FROM cohort_with_exclusions
  WHERE los >= 1
),
dest_agg AS (
  SELECT 
    los_group,
    discharge_location,
    COUNT(*) AS count_dest
  FROM cohort_with_groups
  GROUP BY los_group, discharge_location
),
grouped_dest AS (
  SELECT 
    los_group,
    STRING_AGG(CONCAT(discharge_location, ': ', CAST(count_dest AS STRING)), ', ' ORDER BY count_dest DESC) AS destinations
  FROM dest_agg
  GROUP BY los_group
)
SELECT 
  c.los_group,
  COUNT(*) AS total_patients,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  gd.destinations
FROM cohort_with_groups c
LEFT JOIN grouped_dest gd
  ON c.los_group = gd.los_group
GROUP BY c.los_group, gd.destinations
ORDER BY 
  CASE c.los_group
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '>=8' THEN 3
  END;