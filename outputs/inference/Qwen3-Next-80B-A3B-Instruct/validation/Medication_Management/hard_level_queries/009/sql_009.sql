WITH aki_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(d_icd.long_title) LIKE '%acute kidney injury%'
    AND LOWER(d_icd.long_title) LIKE '%kidney%'
),

med_complexity AS (
  SELECT hadm_id, COUNT(DISTINCT drug) AS med_complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IN (SELECT hadm_id FROM aki_patients)
  GROUP BY hadm_id
),

readmission_30d AS (
  SELECT a1.hadm_id,
         CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d_flag
  FROM aki_patients a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND DATE_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
),

anticoag_opioid AS (
  SELECT p.hadm_id,
         MAX(CASE WHEN LOWER(p.drug) IN (
           'warfarin', 'heparin', 'enoxaparin', 'dabigatran', 'rivaroxaban', 'apixaban', 'edoxaban',
           'clopidogrel', 'aspirin', 'ticagrelor', 'prasugrel'
         ) THEN 1 ELSE 0 END) AS has_anticoagulant,
         MAX(CASE WHEN LOWER(p.drug) IN (
           'morphine', 'oxycodone', 'hydromorphone', 'fentanyl', 'codeine', 'hydrocodone', 'methadone', 'tramadol'
         ) THEN 1 ELSE 0 END) AS has_opioid
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE p.hadm_id IN (SELECT hadm_id FROM aki_patients)
  GROUP BY p.hadm_id
),

final_data AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    mc.med_complexity_score,
    COALESCE(r.readmit_30d_flag, 0) AS readmit_30d_flag,
    COALESCE(ao.has_anticoagulant, 0) AS has_anticoagulant,
    COALESCE(ao.has_opioid, 0) AS has_opioid,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM aki_patients a
  JOIN med_complexity mc ON a.hadm_id = mc.hadm_id
  LEFT JOIN readmission_30d r ON a.hadm_id = r.hadm_id
  LEFT JOIN anticoag_opioid ao ON a.hadm_id = ao.hadm_id
),

quintile_data AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY med_complexity_score) AS quintile
  FROM final_data
)

SELECT
  quintile,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) * 100 AS inpatient_mortality_pct,
  AVG(readmit_30d_flag) * 100 AS readmission_30d_pct,
  SUM(has_anticoagulant * has_opioid) AS anticoagulant_opioid_coadmin_count
FROM quintile_data
GROUP BY quintile
ORDER BY quintile;