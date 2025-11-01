WITH aki_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 9 AND icd_code IN ('5849'))  -- ICD-9: Acute kidney failure, unspecified
    OR (icd_version = 10 AND icd_code IN ('N170', 'N171', 'N172', 'N178', 'N179'))
  )
),
cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 84 AND 94
),
aki_admissions AS (
  SELECT DISTINCT c.*
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON c.hadm_id = di.hadm_id
  JOIN aki_codes ac ON di.icd_code = ac.icd_code
),
medication_complexity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT LOWER(drug)) AS drug_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY hadm_id
),
opioid_anticoagulant AS (
  SELECT
    hadm_id,
    LOGICAL_OR(LOWER(drug) LIKE '%warfarin%' OR LOWER(drug) LIKE '%heparin%' OR
               LOWER(drug) LIKE '%enoxaparin%' OR LOWER(drug) LIKE '%apixaban%' OR
               LOWER(drug) LIKE '%rivaroxaban%' OR LOWER(drug) LIKE '%dabigatran%' OR
               LOWER(drug) LIKE '%edoxaban%' OR LOWER(drug) LIKE '%dalteparin%') AS has_anticoagulant,
    LOGICAL_OR(LOWER(drug) LIKE '%morphine%' OR LOWER(drug) LIKE '%fentanyl%' OR
               LOWER(drug) LIKE '%hydromorphone%' OR LOWER(drug) LIKE '%oxycodone%' OR
               LOWER(drug) LIKE '%hydrocodone%' OR LOWER(drug) LIKE '%codeine%' OR
               LOWER(drug) LIKE '%oxymorphone%' OR LOWER(drug) LIKE '%meperidine%') AS has_opioid
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY hadm_id
),
readmissions AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
),
cohort_with_meds AS (
  SELECT
    aki.*,
    mc.drug_count,
    COALESCE(oa.has_anticoagulant, FALSE) AS has_anticoagulant,
    COALESCE(oa.has_opioid, FALSE) AS has_opioid,
    COALESCE(ra.readmitted_30d, 0) AS readmitted_30d
  FROM aki_admissions aki
  LEFT JOIN medication_complexity mc ON aki.hadm_id = mc.hadm_id
  LEFT JOIN opioid_anticoagulant oa ON aki.hadm_id = oa.hadm_id
  LEFT JOIN readmissions ra ON aki.hadm_id = ra.hadm_id
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY drug_count) AS quintile
  FROM cohort_with_meds
)
SELECT
  quintile,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS inpatient_mortality_rate,
  AVG(CAST(readmitted_30d AS FLOAT64)) AS readmission_30d_rate,
  SUM(CASE WHEN has_anticoagulant AND has_opioid THEN 1 ELSE 0 END) AS anticoagulant_opioid_coadmin_count
FROM quintiles
GROUP BY quintile
ORDER BY quintile;