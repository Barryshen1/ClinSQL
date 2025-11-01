WITH target_admissions AS (
  SELECT 
    adm.hadm_id,
    pat.subject_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.anchor_year,
    -- Calculate age at admission per MIMIC-IV standards
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    -- Filter age 44-54
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 44 AND 54
    -- Intracranial hemorrhage (ICD-10 I60/I61/I62)
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_version = 10
        AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%')
    )
),
complications AS (
  SELECT 
    hadm_id,
    -- Cardiac complications: ICD-10 I20-I52
    MAX(CASE WHEN icd_version = 10 AND LEFT(icd_code, 3) BETWEEN 'I20' AND 'I52' THEN 1 ELSE 0 END) AS has_cardiac,
    -- Neurologic complications: ICD-10 G00-G99 (excludes primary I60-I62)
    MAX(CASE WHEN icd_version = 10 AND LEFT(icd_code, 3) BETWEEN 'G00' AND 'G99' THEN 1 ELSE 0 END) AS has_neuro
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    ta.*,
    COALESCE(comp.has_cardiac, 0) AS cardiac_complication,
    COALESCE(comp.has_neuro, 0) AS neuro_complication,
    -- Length of stay in days
    DATETIME_DIFF(ta.dischtime, ta.admittime, DAY) AS los
  FROM target_admissions ta
  LEFT JOIN complications comp
    ON ta.hadm_id = comp.hadm_id
),
quartiles AS (
  SELECT 
    *,
    -- Assign risk quartiles using anchor_age as proxy (replace with actual composite score if available)
    NTILE(4) OVER (ORDER BY anchor_age) AS risk_quartile
  FROM cohort
)
SELECT 
  risk_quartile,
  COUNT(*) AS patient_count,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(cardiac_complication) AS cardiac_complication_rate,
  AVG(neuro_complication) AS neuro_complication_rate,
  -- Median LOS for survivors only (non-survivors set to NULL)
  APPROX_QUANTILES(IF(hospital_expire_flag = 0, los, NULL), 100)[OFFSET(50)] AS median_los_survivors
FROM quartiles
GROUP BY risk_quartile
ORDER BY risk_quartile;