WITH eligible_patients AS (
  -- Male patients aged 56-66
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 56 AND 66
),
mcs_codes AS (
  -- ICD procedure codes that correspond to mechanical circulatory support
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS di
  WHERE LOWER(di.long_title) LIKE '%ecmo%'
     OR LOWER(di.long_title) LIKE '%extracorporeal%'
     OR LOWER(di.long_title) LIKE '%balloon%'
     OR LOWER(di.long_title) LIKE '%intra-aortic%'
     OR LOWER(di.long_title) LIKE '%ventricular%'
     OR LOWER(di.long_title) LIKE '%assist%'
     OR LOWER(di.long_title) LIKE '%bypass%'
     OR LOWER(di.long_title) LIKE '%heart-lung%'
),
per_patient_counts AS (
  SELECT ep.subject_id,
         COUNT(DISTINCT CASE WHEN mc.icd_code IS NOT NULL THEN pi.icd_code END) AS mcs_count
  FROM eligible_patients AS ep
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    ON ep.subject_id = pi.subject_id
  LEFT JOIN mcs_codes AS mc
    ON pi.icd_code = mc.icd_code
   AND pi.icd_version = mc.icd_version
  GROUP BY ep.subject_id
)
SELECT STDDEV_SAMP(COALESCE(mcs_count, 0)) AS sd_mcs_per_patient
FROM per_patient_counts;