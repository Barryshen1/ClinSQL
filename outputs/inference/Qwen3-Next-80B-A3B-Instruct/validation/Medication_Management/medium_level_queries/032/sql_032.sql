SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di1
    ON i.hadm_id = di1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did1
    ON di1.icd_code = did1.icd_code AND di1.icd_version = did1.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
    ON i.hadm_id = di2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did2
    ON di2.icd_code = did2.icd_code AND di2.icd_version = did2.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND LOWER(did1.long_title) LIKE '%diabetes%'
    AND LOWER(did2.long_title) LIKE '%acute%heart failure%'
    AND i.los >= 1  -- 24 hours = 1 day
);