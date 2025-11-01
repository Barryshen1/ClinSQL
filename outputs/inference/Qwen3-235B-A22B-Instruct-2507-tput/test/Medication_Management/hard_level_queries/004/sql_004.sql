WITH admissions_with_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
),
stroke_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%acute ischemic stroke%'
    OR (icd_version = 10 AND icd_code LIKE 'I63%')
    OR (icd_version = 9 AND icd_code LIKE '434%')
),
stroke_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.age_at_admission
  FROM admissions_with_age a
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN stroke_icd s
    ON di.icd_code = s.icd_code AND di.icd_version = s.icd_version
  WHERE a.gender = 'F'
    AND a.age_at_admission BETWEEN 48 AND 58
),
nti_drugs AS (
  SELECT drug FROM (
    SELECT 'warfarin' AS drug UNION ALL
    SELECT 'digoxin' UNION ALL
    SELECT 'phenytoin' UNION ALL
    SELECT 'carbamazepine' UNION ALL
    SELECT 'theophylline' UNION ALL
    SELECT 'cyclosporine' UNION ALL
    SELECT 'tacrolimus'
  )
),
cyp3a4_inhibitors AS (
  SELECT drug FROM (
    SELECT 'clarithromycin' AS drug UNION ALL
    SELECT 'erythromycin' UNION ALL
    SELECT 'ketoconazole' UNION ALL
    SELECT 'itraconazole' UNION ALL
    SELECT 'voriconazole' UNION ALL
    SELECT 'posaconazole' UNION ALL
    SELECT 'ritonavir' UNION ALL
    SELECT 'indinavir' UNION ALL
    SELECT 'nelfinavir' UNION ALL
    SELECT 'saquinavir' UNION ALL
    SELECT 'diltiazem' UNION ALL
    SELECT 'verapamil' UNION ALL
    SELECT 'grapefruit juice'
  )
),
nti_prescriptions AS (
  SELECT DISTINCT
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  JOIN nti_drugs n ON LOWER(p.drug) LIKE '%' || n.drug || '%'
  WHERE p.starttime IS NOT NULL
),
cyp3a4_prescriptions AS (
  SELECT DISTINCT
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  JOIN cyp3a4_inhibitors c ON LOWER(p.drug) LIKE '%' || c.drug || '%'
  WHERE p.starttime IS NOT NULL
),
cyp3a4_nti_overlap AS (
  SELECT DISTINCT
    n.hadm_id
  FROM nti_prescriptions n
  JOIN cyp3a4_prescriptions c
    ON n.hadm_id = c.hadm_id
    AND n.starttime < COALESCE(c.stoptime, '9999-12-31')
    AND c.starttime < COALESCE(n.stoptime, '9999-12-31')
),
stroke_with_drg AS (
  SELECT
    sp.*,
    d.drg_severity,
    DATETIME_DIFF(sp.dischtime, sp.admittime, HOUR) / 24.0 AS los_days
  FROM stroke_patients sp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.drgcodes d
    ON sp.hadm_id = d.hadm_id AND d.drg_type = 'HCFA'
  WHERE d.drg_code IS NOT NULL  -- Ensure valid DRG record
),
cyp3a4_nti_group AS (
  SELECT
    'CYP3A4_NTI' AS group_label,
    AVG(COALESCE(s.drg_severity, 0)) AS avg_complexity,
    AVG(s.los_days) AS avg_los,
    AVG(s.hospital_expire_flag) AS mortality_rate
  FROM stroke_with_drg s
  WHERE s.hadm_id IN (SELECT hadm_id FROM cyp3a4_nti_overlap)
),
cohort_group AS (
  SELECT
    'COHORT' AS group_label,
    AVG(COALESCE(s.drg_severity, 0)) AS avg_complexity,
    AVG(s.los_days) AS avg_los,
    AVG(s.hospital_expire_flag) AS mortality_rate
  FROM stroke_with_drg s
),
top_quartile_group AS (
  SELECT
    'TOP_QUARTILE' AS group_label,
    AVG(COALESCE(s.drg_severity, 0)) AS avg_complexity,
    AVG(s.los_days) AS avg_los,
    AVG(s.hospital_expire_flag) AS mortality_rate
  FROM stroke_with_drg s
  WHERE s.drg_severity = 3
)
SELECT * FROM cyp3a4_nti_group
UNION ALL
SELECT * FROM cohort_group
UNION ALL
SELECT * FROM top_quartile_group
ORDER BY group_label;