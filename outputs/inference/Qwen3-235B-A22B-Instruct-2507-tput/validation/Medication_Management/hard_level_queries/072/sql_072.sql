with DKA. Among female inpatients 84–94 with DKA during first 48h, 
compare those with vs without hyperkalemia-risk drug interactions: mean medication complexity and percentile, 
LOS and mortality; report LOS and mortality for top complexity quartile.
*/

WITH patients_age AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
),
admissions_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    pa.anchor_age,
    pa.anchor_year,
    pa.gender,
    (pa.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pa.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN patients_age pa ON a.subject_id = pa.subject_id
  WHERE (pa.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pa.anchor_year)) BETWEEN 84 AND 94
),
dka_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    (icd_version = 9 AND icd_code = '2501')
    OR (icd_version = 10 AND SUBSTR(icd_code, 1, 5) IN ('E10.1', 'E11.1', 'E13.1'))
  )
),
dka_patients AS (
  SELECT DISTINCT
    aa.*
  FROM admissions_age aa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON aa.hadm_id = di.hadm_id
  JOIN dka_codes dc
    ON di.icd_code = dc.icd_code AND di.icd_version = dc.icd_version
),
meds_48h AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  JOIN dka_patients dka
    ON p.subject_id = dka.subject_id AND p.hadm_id = dka.hadm_id
  WHERE p.starttime >= dka.admittime
    AND p.starttime <= DATETIME_ADD(dka.admittime, INTERVAL 48 HOUR)
    AND p.drug IS NOT NULL
),
hyperkalemia_drugs AS (
  SELECT
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%potassium chloride%' THEN 'k_supplement'
      WHEN LOWER(drug) IN ('spironolactone', 'eplerenone') THEN 'k_sparing_diuretic'
      WHEN LOWER(drug) LIKE '%amiloride%' OR LOWER(drug) LIKE '%triamterene%' THEN 'k_sparing_diuretic'
      WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%' OR LOWER(drug) LIKE '%ramipril%'
        OR LOWER(drug) LIKE '%quinapril%' OR LOWER(drug) LIKE '%benazepril%' OR LOWER(drug) LIKE '%captopril%'
        OR LOWER(drug) LIKE '%fosinopril%' OR LOWER(drug) LIKE '%moexipril%' OR LOWER(drug) LIKE '%perindopril%'
        OR LOWER(drug) LIKE '%trandolapril%' THEN 'ace_inhibitor'
      WHEN LOWER(drug) LIKE '%losartan%' OR LOWER(drug) LIKE '%valsartan%' OR LOWER(drug) LIKE '%irbesartan%'
        OR LOWER(drug) LIKE '%candesartan%' OR LOWER(drug) LIKE '%olmesartan%' OR LOWER(drug) LIKE '%telmisartan%'
        OR LOWER(drug) LIKE '%eprosartan%' OR LOWER(drug) LIKE '%azilsartan%' THEN 'arb'
      WHEN LOWER(drug) LIKE '%sulfonylurea%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glipizide%'
        OR LOWER(drug) LIKE '%gliclazide%' OR LOWER(drug) LIKE '%glimepiride%' THEN 'sulfonylurea'
      ELSE NULL
    END AS risk_class
  FROM meds_48h
  WHERE LOWER(drug) IN (
    'potassium chloride', 'spironolactone', 'eplerenone', 'amiloride', 'triamterene',
    'lisinopril', 'enalapril', 'ramipril', 'quinapril', 'benazepril', 'captopril',
    'fosinopril', 'moexipril', 'perindopril', 'trandolapril',
    'losartan', 'valsartan', 'irbesartan', 'candesartan', 'olmesartan', 'telmisartan', 'eprosartan', 'azilsartan',
    'glyburide', 'glipizide', 'gliclazide', 'glimepiride'
  ) OR LOWER(drug) LIKE '%potassium chloride%'
     OR LOWER(drug) LIKE '%sulfonylurea%'
),
patient_risk_classes AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT risk_class) AS num_risk_classes
  FROM hyperkalemia_drugs
  WHERE risk_class IS NOT NULL
  GROUP BY subject_id, hadm_id
),
with_interaction AS (
  SELECT
    subject_id,
    hadm_id,
    CASE WHEN num_risk_classes >= 2 THEN 1 ELSE 0 END AS has_interaction
  FROM patient_risk_classes
),
medication_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS complexity
  FROM meds_48h
  GROUP BY subject_id, hadm_id
),
combined AS (
  SELECT
    dka.subject_id,
    dka.hadm_id,
    dka.admittime,
    dka.dischtime,
    dka.hospital_expire_flag,
    COALESCE(mc.complexity, 0) AS complexity,
    COALESCE(wi.has_interaction, 0) AS has_interaction,
    DATETIME_DIFF(dka.dischtime, dka.admittime, HOUR) / 24.0 AS los_days
  FROM dka_patients dka
  LEFT JOIN medication_complexity mc
    ON dka.subject_id = mc.subject_id AND dka.hadm_id = mc.hadm_id
  LEFT JOIN with_interaction wi
    ON dka.subject_id = wi.subject_id AND dka.hadm_id = wi.hadm_id
),
ranked AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY complexity) AS complexity_percentile,
    NTILE(4) OVER (ORDER BY complexity DESC) AS complexity_quartile
  FROM combined
)
-- Result 1: Compare groups (with vs without interaction)
SELECT
  'with_interaction' AS group_type,
  AVG(complexity) AS mean_complexity,
  AVG(complexity_percentile) AS mean_percentile,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM ranked
WHERE has_interaction = 1
GROUP BY has_interaction

UNION ALL

SELECT
  'without_interaction' AS group_type,
  AVG(complexity) AS mean_complexity,
  AVG(complexity_percentile) AS mean_percentile,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS;