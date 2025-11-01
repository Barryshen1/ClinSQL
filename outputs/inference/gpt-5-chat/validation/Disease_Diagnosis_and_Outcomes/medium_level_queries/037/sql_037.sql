WITH sepsis_icd AS (
  SELECT 9 AS icd_version, code
  FROM UNNEST([
    '99591', -- sepsis
    '99592', -- severe sepsis
    '0380','0381','0382','0383','0384','0388','0389', -- septicemia
    '78552' -- septic shock
  ]) AS code
  UNION ALL
  SELECT 10 AS icd_version, code
  FROM UNNEST([
    'A400','A401','A402','A403','A408','A409', -- strep sepsis
    'A410','A411','A412','A413','A414','A4150','A4151','A4152','A4153','A4159','A418','A419', -- staph and others
    'R6520','R6521' -- severe sepsis without/with septic shock
  ]) AS code
),
shock_codes AS (
  SELECT 9 AS icd_version, code
  FROM UNNEST(['78552']) AS code
  UNION ALL
  SELECT 10 AS icd_version, code
  FROM UNNEST(['R6521']) AS code
),
-- Identify admissions with sepsis and shock flag
sepsis_adm AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN scshock.code IS NOT NULL THEN 1 ELSE 0 END) AS septic_shock
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN sepsis_icd sc
    ON di.icd_version = sc.icd_version
    AND di.icd_code = sc.code
  LEFT JOIN shock_codes scshock
    ON di.icd_version = scshock.icd_version
    AND di.icd_code = scshock.code
  GROUP BY di.subject_id, di.hadm_id
),
-- Comorbidity counts (excluding sepsis codes)
comorbidities AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN sepsis_icd sc
    ON di.icd_version = sc.icd_version
    AND di.icd_code = sc.code
  WHERE sc.code IS NULL -- exclude sepsis codes
  GROUP BY di.subject_id, di.hadm_id
),
-- Combine with patients and admissions
base AS (
  SELECT
    p.subject_id,
    adm.hadm_id,
    sa.septic_shock,
    c.comorbidity_count,
    adm.hospital_expire_flag,
    adm.admission_type,
    CAST(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS INT64) AS los_days
  FROM sepsis_adm sa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON sa.hadm_id = adm.hadm_id
    AND sa.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON sa.subject_id = p.subject_id
  LEFT JOIN comorbidities c
    ON sa.subject_id = c.subject_id
    AND sa.hadm_id = c.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
final AS (
  SELECT
    CASE WHEN septic_shock = 1 THEN 'Septic shock' ELSE 'No shock' END AS sepsis_severity,
    CASE WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
         WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
         WHEN los_days >= 8 THEN '>=8'
         ELSE 'Unknown' END AS los_group,
    admission_type,
    COUNT(*) AS n_admissions,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_percent,
    AVG(comorbidity_count) AS mean_comorbidity_count
  FROM base
  GROUP BY sepsis_severity, los_group, admission_type
)
SELECT *
FROM final
ORDER BY sepsis_severity, los_group, admission_type;