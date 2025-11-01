WITH principal_dehydration AS (
  SELECT di.subject_id,
         di.hadm_id,
         di.icd_code,
         di.icd_version,
         dd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND UPPER(dd.long_title) LIKE '%DEHYDRAT%'
)

SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN principal_dehydration pd
  ON a.hadm_id = pd.hadm_id
 AND a.subject_id = pd.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND UPPER(COALESCE(a.insurance, '')) LIKE '%MEDICARE%'
  AND (
        UPPER(COALESCE(a.admission_location, '')) LIKE '%SNF%'
     OR UPPER(COALESCE(a.admission_location, '')) LIKE '%SKILLED%'
     OR UPPER(COALESCE(a.admission_location, '')) LIKE '%NURSING%'
  );