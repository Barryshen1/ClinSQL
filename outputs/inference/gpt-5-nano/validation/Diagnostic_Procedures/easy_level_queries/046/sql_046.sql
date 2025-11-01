WITH eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE p.gender = 'M'
    AND p.anchor_age >= 80
    AND p.anchor_age <= 90
),

-- 2) Admissions for those patients
admissions_for_patients AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN eligible_patients AS e ON e.subject_id = a.subject_id
),

-- 3) Identify MCS procedures per admission by mapping ICD codes to long titles
--     Keep only those admissions that contain MCS-related procedures
mcs_per_admission AS (
  SELECT
    afp.subject_id,
    afp.hadm_id,
    COUNT(DISTINCT LOWER(di.long_title)) AS mcs_count
  FROM admissions_for_patients AS afp
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pc
    ON pc.subject_id = afp.subject_id
   AND pc.hadm_id = afp.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS di
    ON di.icd_code = pc.icd_code
   AND di.icd_version = pc.icd_version
  WHERE LOWER(di.long_title) LIKE '%ventricular%'
     OR LOWER(di.long_title) LIKE '%ecmo%'
     OR LOWER(di.long_title) LIKE '%extracorporeal%'
     OR LOWER(di.long_title) LIKE '%intra-aortic balloon%'
     OR LOWER(di.long_title) LIKE '%balloon pump%'
     OR LOWER(di.long_title) LIKE '%ventricular assist device%'
  GROUP BY afp.subject_id, afp.hadm_id
)

-- 4) For each patient, take the maximum number of distinct MCS types observed in a single admission
SELECT
  MAX(mcs_count) AS max_distinct_mcs_per_patient
FROM mcs_per_admission;